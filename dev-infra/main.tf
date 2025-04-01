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
  filename      = "${path.module}/lambda/fetch_stock_market_data.zip"

  timeout = 120
  memory_size = 512

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      CONFIG_BUCKET_NAME = "terraform-stockvisionai-infra"
      CONFIG_FILE_PATH   = "configs.json"
      RAW_BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
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
  filename      = "${path.module}/lambda/partition_consolidated_data.zip"

  timeout = 120
  memory_size = 512

  layers = ["arn:aws:lambda:ap-south-1:336392948345:layer:AWSSDKPandas-Python39:28"]

  environment {
    variables = {
      RAW_BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
    }
  }
}

# S3 Trigger for Partition Lambda
resource "aws_s3_bucket_notification" "consolidated_data_notification" {
  bucket = aws_s3_bucket.raw_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.partition_consolidated_data.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "consolidated_raw/"
    filter_suffix       = ".csv"
  }
}

resource "aws_lambda_permission" "allow_partition_trigger" {
  statement_id  = "AllowS3Invocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.partition_consolidated_data.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# IAM Roles and Policies
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

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.s3_read_write_policy.arn
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
