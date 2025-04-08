variable "bucket_suffix" {
  description = "Environment-specific suffix"
  type        = string
}
variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
}
variable "apca_api_key_id" {
  description = "API key for id fetching news"
  type        = string
  sensitive   = true
}
variable "apca_api_secret_key" {
  description = "API secret key for fetching news"
  type        = string
  sensitive   = true
}

variable "news_api_url" {
  description = "Base URL for the news API"
  type        = string
}

