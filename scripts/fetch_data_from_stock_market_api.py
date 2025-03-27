import yfinance as yf
import pandas as pd
import boto3
import json
import os
from botocore.exceptions import NoCredentialsError


def load_config(config_path="/Users/dev/Desktop/Programming/Devlopment/StockVisionAI/config/configs.json"):
    """
    Load configuration from a JSON file.

    :param config_path: Path to the configuration file
    :return: Dictionary containing configuration values
    """
    with open(config_path, "r") as config_file:
        config = json.load(config_file)
    return config

def fetch_stock_data(ticker, start_date, end_date):
    """
    Fetch historical stock data using yfinance.

    :param ticker: Stock ticker symbol (e.g., 'AAPL')
    :param start_date: Start date in 'YYYY-MM-DD' format
    :param end_date: End date in 'YYYY-MM-DD' format
    :return: Pandas DataFrame containing historical stock data
    """
    print(f"Fetching data for {ticker} from {start_date} to {end_date}...")
    data = yf.download(ticker, start=start_date, end=end_date)
    if data.empty:
        print(f"No data found for {ticker}.")
        return None
    print(f"Data fetched successfully for {ticker}.")
    return data

def save_to_csv(data, filename, raw_data_dir):
    """
    Save DataFrame to a CSV file in the specified directory.

    :param data: Pandas DataFrame to save
    :param filename: Name of the CSV file
    :param raw_data_dir: Directory to save the file in
    """
    
    file_path = os.path.join(raw_data_dir, filename) 
    data.to_csv(file_path)
    print(f"Data saved locally as {file_path}.")
    return file_path

def upload_to_s3(file_path, bucket_name, aws_access_key, aws_secret_key):
    """
    Upload a file to an S3 bucket.

    :param file_path: Path to the file to upload
    :param bucket_name: Target S3 bucket name
    :param aws_access_key: AWS access key
    :param aws_secret_key: AWS secret key
    """
    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key,
    )
    try:
        # Upload file to S3 using the filename as the key
        s3.upload_file(file_path, bucket_name, os.path.basename(file_path))
        print(f"File {os.path.basename(file_path)} uploaded to S3 bucket {bucket_name} successfully.")
    except FileNotFoundError:
        print(f"File {file_path} not found.")
    except NoCredentialsError:
        print("AWS credentials not available.")

def main():
    config=load_config()

    # Extract values from config
    aws_access_key = config["aws"]["access_key"]
    aws_secret_key = config["aws"]["secret_key"]
    s3_bucket_name = config["aws"]["s3_bucket_name"]

    ticker = config["stock_data"]["ticker"]
    start_date = config["stock_data"]["start_date"]
    end_date = config["stock_data"]["end_date"]

    raw_data_dir = config["paths"]["raw_data_dir"]
    local_filename = f"{ticker}_historical_data.csv"

    # Fetch stock data
    data = fetch_stock_data(ticker, start_date, end_date)
    if data is not None:
        # Save data locally
        file_path = save_to_csv(data, local_filename, raw_data_dir)

        # Upload data to S3
        upload_to_s3(file_path, s3_bucket_name, aws_access_key, aws_secret_key)

if __name__ == "__main__":
    main()
