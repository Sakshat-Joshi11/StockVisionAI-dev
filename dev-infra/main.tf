terraform {
  backend "s3" {
    bucket         = "terraform-stockvisionai-infra"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
  }
}

provider "aws" {
  region = var.region
}

# S3 Buckets
resource "aws_s3_bucket" "raw_data" {
  bucket        = "stock-market-raw-data${var.bucket_suffix}"
  force_destroy = true
}

resource "aws_s3_bucket" "processed_data" {
  bucket        = "stock-market-processed-data${var.bucket_suffix}"
  force_destroy = true
}

resource "aws_s3_bucket" "curated_data" {
  bucket        = "stock-market-curated-data${var.bucket_suffix}"
  force_destroy = true
}

# Lambda Function for Fetching the data from API
resource "aws_lambda_function" "fetch_stock_market_data" {
  function_name = "fetch_stock_market_data${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_to_fetch_stock_market_data.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/fetch_stock_market_data.zip")
  filename         = "${path.module}/lambda/fetch_stock_market_data.zip"

  timeout     = 120
  memory_size = 1024

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      CONFIG_BUCKET_NAME = "terraform-stockvisionai-infra"
      CONFIG_FILE_PATH   = "configs.json"
      RAW_BUCKET_NAME    = "stock-market-raw-data${var.bucket_suffix}"
    }
  }
}

# Lambda Function for Partitioning Consolidated Data
resource "aws_lambda_function" "partition_consolidated_data" {
  function_name = "partition-consolidated-data${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_to_partition_consolidated_csv.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/partition_consolidated_data.zip")
  filename         = "${path.module}/lambda/partition_consolidated_data.zip"

  timeout     = 120
  memory_size = 512

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      RAW_BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
    }
  }
}

# Lambda Function: SQS News Consumer
resource "aws_lambda_function" "sqs_news_consumer" {
  function_name = "sqs-news-consumer${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_for_sqs_news_consumer.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/sqs_news_consumer.zip")
  filename         = "${path.module}/lambda/sqs_news_consumer.zip"

  timeout     = 60
  memory_size = 512

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      RAW_BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
      APCA_API_KEY_ID = "PKJZB25117QC6OYXPH75"
      APCA_API_SECRET_KEY = "bhZfXzjBAAfVuqHOpjEw5UDzBlf4tAMaRAvDwjNR"
      NEWS_API_URL = "https://data.alpaca.markets/v1beta1/news" 
    }
  }
}

# Lambda Function: SQS to SNS Producer
resource "aws_lambda_function" "sqs_news_producer" {
  function_name = "sqs-to-sns-producer${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_for_sqs_news_producer.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/sqs_news_producer.zip")
  filename         = "${path.module}/lambda/sqs_news_producer.zip"

  timeout     = 300
  memory_size = 2048

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      RAW_BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
      TOPIC_ARN = aws_sns_topic.stock_alerts.arn
      SQS_QUEUE_URL = "https://sqs.ap-south-1.amazonaws.com/597088017947/stock-news-queue"
      APCA_API_KEY_ID = "PKJZB25117QC6OYXPH75"
      APCA_API_SECRET_KEY = "bhZfXzjBAAfVuqHOpjEw5UDzBlf4tAMaRAvDwjNR"
      NEWS_API_URL = "https://data.alpaca.markets/v1beta1/news"
    }
  }
}

resource "aws_lambda_event_source_mapping" "trigger_consumer_from_sqs" {
  event_source_arn = aws_sqs_queue.stock_news_queue.arn
  function_name    = aws_lambda_function.sqs_news_consumer.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_s3_bucket_notification" "s3_triggers" {
  bucket = aws_s3_bucket.raw_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.partition_consolidated_data.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "consolidated_raw/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.sqs_news_producer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "partitioned_raw/"
  }

  depends_on = [
    aws_lambda_permission.allow_partition_trigger,
    aws_lambda_permission.allow_sqs_news_producer
  ]
}

# Permission for Partition Lambda
resource "aws_lambda_permission" "allow_sqs_news_producer" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.partition_consolidated_data.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# Permission for SQS News Producer Lambda
resource "aws_lambda_permission" "allow_partition_trigger" {
  statement_id  = "AllowS3SQSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sqs_news_producer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# SQS Queue
resource "aws_sqs_queue" "stock_news_queue" {
  name = "stock-news-queue"
  visibility_timeout_seconds = 300
}

resource "aws_iam_policy" "sqs_read_policy" {
  name = "sqs-read-policy${var.bucket_suffix}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
        Effect   = "Allow",
        Resource = aws_sqs_queue.stock_news_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqs_read_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.sqs_read_policy.arn
}

# IAM Role : Lambda Execution 
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role${var.bucket_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policies : S3 ReadWrite
resource "aws_iam_policy" "s3_read_write_policy" {
  name   = "s3-read-write-policy${var.bucket_suffix}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:PutObject", "s3:GetObject"],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::stock-market-raw-data${var.bucket_suffix}/*",
          "arn:aws:s3:::stock-market-processed-data${var.bucket_suffix}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_logging_policy" {
  name   = "lambda-logging-policy${var.bucket_suffix}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "logs:CreateLogGroup",
        Effect   = "Allow",
        Resource = "arn:aws:logs:${var.region}:*:*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.s3_read_write_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_logging_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

# SNS Topic
resource "aws_sns_topic" "stock_alerts" {
  name = "stock-alerts${var.bucket_suffix}"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "process_stock_data_logs" {
  name              = "/aws/lambda/process-stock-data-dev"
  retention_in_days = 30
}

# Athena Database
resource "aws_athena_database" "stock_analysis_dev" {
  name   = "stock_analysis_dev"
  bucket = aws_s3_bucket.processed_data.id
}

# Glue Crawler to clean Raw Partitioned Data
resource "aws_glue_crawler" "partitioned_raw_crawler" {
  name         = "partitioned_raw_crawler"
  role         = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.partitioned_stock_data.name
  description  = "Crawler for partitioned raw stock data"

  s3_target {
      path = "s3://stock-market-raw-data-dev/partitioned_raw/"
    }
  


  table_prefix = "partitioned_raw_"

  configuration = jsonencode({
    "Version"    : 1.0,
    "Grouping"   : {
      "TableGroupingPolicy" : "CombineCompatibleSchemas"
    }
  })
}

# Glue Crawler for clean Raw Partitioned Data
resource "aws_glue_crawler" "partitioned_cleaned_crawler" {
  name         = "partitioned_cleaned_crawler"
  role         = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.cleaned_partitioned_stock_data.name
  description  = "Crawler for partitioned raw stock data"

  s3_target {
      path = "s3://stock-market-raw-data-dev/cleaned_partitioned_data/"
    }
  


  table_prefix = "partitioned_cleaned_"

  configuration = jsonencode({
    "Version"    : 1.0,
    "Grouping"   : {
      "TableGroupingPolicy" : "CombineCompatibleSchemas"
    }
  })
}
resource "aws_glue_catalog_database" "partitioned_stock_data" {
  name = "partitioned_stock_data"
}
resource "aws_glue_catalog_database" "cleaned_partitioned_stock_data" {
  name = "cleaned_partitioned_stock_data"
}

resource "aws_iam_role" "glue_role" {
  name = "glue-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "glue.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "glue_policy" {
  name   = "glue-access-policy"
  role   = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   : "Allow",
        Action   : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource : [
          "arn:aws:s3:::stock-market-raw-data-dev",
          "arn:aws:s3:::stock-market-raw-data-dev/*"
        ]
      },
      {
        Effect   : "Allow",
        Action   : [
          "glue:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource : "*"
      }
    ]
  })
}
resource "aws_s3_object" "glue_etl_script" {
  bucket = "stock-market-raw-data-dev"
  key    = "scripts/normalize_stock_data.py"
  source = "/Users/dev/Desktop/Programming/Devlopment/StockVisionAI/scripts/normalize_stock_data.py" 
}

resource "aws_glue_job" "etl_job" {
  name        = "normalize-stock-data"
  role_arn    = aws_iam_role.glue_etl_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://stock-market-raw-data-dev/scripts/normalize_stock_data.py"
    python_version  = "3"
  }

  max_capacity        = 2  # Number of DPUs (adjust based on data size)
  timeout             = 20 # Maximum runtime in minutes
  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-enable"
    "--TempDir"             = "s3://stock-market-raw-data-dev/temp/"
  }

  glue_version = "3.0"
}
resource "aws_iam_role" "glue_etl_role" {
  name = "glue-etl-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
      },
    ]
  })
}

resource "aws_iam_policy" "glue_etl_policy" {
  name        = "glue-etl-policy"
  description = "Policy for Glue ETL Job"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::stock-market-raw-data-dev/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "glue:*",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_glue_etl_policy" {
  role       = aws_iam_role.glue_etl_role.name
  policy_arn = aws_iam_policy.glue_etl_policy.arn
}

# NoteBook - SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name               = "sagemaker-notebook-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sagemaker.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_policy_attachment" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_notebook_instance" "notebook" {
  name                 = "stockvisionai-notebook"
  instance_type        = "ml.t2.medium"  
  role_arn             = aws_iam_role.sagemaker_role.arn

  tags = {
    Project = "StockVisionAI"
  }
}