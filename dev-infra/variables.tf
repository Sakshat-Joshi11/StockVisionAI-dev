variable "bucket_suffix" {
  description = "Environment-specific suffix"
  type        = string
}
variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
}
variable "news_api_key" {
  description = "API key for fetching news"
  type        = string
  sensitive   = true
}

variable "news_api_url" {
  description = "Base URL for the news API"
  type        = string
}

