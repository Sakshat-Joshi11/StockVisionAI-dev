import yfinance as yf
import pandas as pd
import boto3
from botocore.exceptions import NoCredentialsError

# AWS S3 Configuration
AWS_ACCESS_KEY = "AKIAYWBJYDYNSPUPOKXN"
AWS_SECRET_KEY = "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"
S3_BUCKET_NAME = "stock-market-raw-data-dev"

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

def save_to_csv(data, filename):
    """
    Save DataFrame to a CSV file.

    :param data: Pandas DataFrame to save
    :param filename: Name of the CSV file
    """
    data.to_csv(filename)
    print(f"Data saved locally as {filename}.")

def upload_to_s3(filename, bucket_name, aws_access_key, aws_secret_key):
    """
    Upload a file to an S3 bucket.

    :param filename: File to upload
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
        s3.upload_file(filename, bucket_name, filename)
        print(f"File {filename} uploaded to S3 bucket {bucket_name} successfully.")
    except FileNotFoundError:
        print(f"File {filename} not found.")
    except NoCredentialsError:
        print("AWS credentials not available.")

def main():
    # Define parameters
    ticker = "AAPL" 
    start_date = "2020-01-01"
    end_date = "2023-12-31"
    local_filename = f"{ticker}_historical_data.csv"

    # Fetch stock data
    data = fetch_stock_data(ticker, start_date, end_date)
    if data is not None:
        # Save data locally
        save_to_csv(data, local_filename)

        # Upload data to S3 
        upload_to_s3(local_filename, S3_BUCKET_NAME, AWS_ACCESS_KEY, AWS_SECRET_KEY)

if __name__ == "__main__":
    main()
