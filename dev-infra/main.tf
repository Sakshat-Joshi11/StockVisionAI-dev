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

# IAM Role
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

# IAM Policies
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
