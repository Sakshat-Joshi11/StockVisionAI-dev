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

resource "aws_s3_bucket" "curated_data"{
  bucket        = "stock-market-curated-data${var.bucket_suffix}"
  force_destroy = true
}
# Lambda Functions
resource "aws_lambda_function" "process_stock_data" {
  function_name = "process-stock-data${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/process_stock_data.zip")
  filename         = "${path.module}/lambda/process_stock_data.zip"

  environment {
    variables = {
      BUCKET_NAME = "stock-market-raw-data${var.bucket_suffix}"
    }
  }
}

resource "aws_lambda_function" "notify_stock_alert" {
  function_name = "notify-stock-alert${var.bucket_suffix}"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_execution_role.arn

  source_code_hash = filebase64sha256("${path.module}/lambda/notify_stock_alert.zip")
  filename         = "${path.module}/lambda/notify_stock_alert.zip"
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

# CloudWatch Metric Alarm
resource "aws_cloudwatch_metric_alarm" "high_error_rate_process_stock_data_dev" {
  alarm_name          = "HighErrorRate-ProcessStockData-Dev"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.stock_alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.process_stock_data.function_name
  }
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
