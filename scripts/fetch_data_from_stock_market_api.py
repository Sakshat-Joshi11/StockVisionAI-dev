import yfinance as yf
import pandas as pd
import boto3
import json
import os
import logging
from botocore.exceptions import NoCredentialsError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("stock_data.log"),
        logging.StreamHandler()
    ]
)

def load_config(config_path="/Users/dev/Desktop/Programming/Devlopment/StockVisionAI/config/configs.json"):
    """
    Load configuration from a JSON file.

    :param config_path: Path to the configuration file
    :return: Dictionary containing configuration values
    """
    try:
        with open(config_path, "r") as config_file:
            config = json.load(config_file)
        logging.info(f"Configuration loaded from {config_path}.")
        return config
    except FileNotFoundError:
        logging.error(f"Configuration file not found at {config_path}.")
        raise
    except json.JSONDecodeError as e:
        logging.error(f"Error decoding JSON configuration: {e}")
        raise

def fetch_stock_data(tickers, start_date, end_date):
    """
    Fetch historical stock data using yfinance.

    :param tickers: Stock tickers symbol (e.g., 'AAPL')
    :param start_date: Start date in 'YYYY-MM-DD' format
    :param end_date: End date in 'YYYY-MM-DD' format
    :return: Pandas DataFrame containing historical stock data
    """
    logging.info(f"Fetching data for {tickers} from {start_date} to {end_date}...")
    try:
        data = yf.download(tickers, start=start_date, end=end_date)
        if data.empty:
            logging.warning(f"No data found for {tickers}.")
            return None
        logging.info(f"Data fetched successfully for {tickers}.")
        return data
    except Exception as e:
        logging.error(f"Error fetching data for {tickers}: {e}")
        return None

def save_to_csv(data, filename, raw_data_dir):
    """
    Save DataFrame to a CSV file in the specified directory.

    :param data: Pandas DataFrame to save
    :param filename: Name of the CSV file
    :param raw_data_dir: Directory to save the file in
    :return: Full file path of the saved file
    """
    try:
        os.makedirs(raw_data_dir, exist_ok=True)
        file_path = os.path.join(raw_data_dir, filename)
        data.to_csv(file_path)
        logging.info(f"Data saved locally as {file_path}.")
        return file_path
    except Exception as e:
        logging.error(f"Error saving data to {filename} in {raw_data_dir}: {e}")
        raise

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
        s3.upload_file(file_path, bucket_name, os.path.basename(file_path))
        logging.info(f"File {os.path.basename(file_path)} uploaded to S3 bucket {bucket_name} successfully.")
    except FileNotFoundError:
        logging.error(f"File {file_path} not found.")
        raise
    except NoCredentialsError:
        logging.error("AWS credentials not available.")
        raise
    except Exception as e:
        logging.error(f"Error uploading {file_path} to S3: {e}")
        raise

def main():
    try:
        # Load configuration
        config = load_config()

        # Extract values from config
        aws_access_key = config["aws"]["access_key"]
        aws_secret_key = config["aws"]["secret_key"]
        s3_bucket_name = config["aws"]["s3_bucket_name"]

        tickers = config["stock_data"]["tickers"]
        start_date = config["stock_data"]["start_date"]
        end_date = config["stock_data"]["end_date"]

        raw_data_dir = config["paths"]["raw_data_dir"]
        local_filename = f"{tickers}_historical_data.csv"

        # Fetch stock data
        data = fetch_stock_data(tickers, start_date, end_date)
        if data is not None:
            # Save data locally
            file_path = save_to_csv(data, local_filename, raw_data_dir)

            # Upload data to S3
            upload_to_s3(file_path, s3_bucket_name, aws_access_key, aws_secret_key)
    except Exception as e:
        logging.error(f"An error occurred in the main function: {e}")

if __name__ == "__main__":
    main()
