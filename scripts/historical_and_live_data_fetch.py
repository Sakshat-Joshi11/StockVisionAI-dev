import yfinance as yf
import pandas as pd
import json
import os
import boto3
from botocore.exceptions import NoCredentialsError

# Load Configuration
def load_config(config_path):
    with open(config_path, "r") as file:
        return json.load(file)

# Fetch Historical Data
def fetch_historical_data(ticker, start_date, end_date, interval):
    print(f"Fetching historical data for {ticker} from {start_date} to {end_date} at {interval} intervals...")
    data = yf.download(ticker, start=start_date, end=end_date, interval=interval)
    if data.empty:
        print(f"No historical data found for {ticker}.")
        return None
    print(f"Historical data fetched successfully for {ticker}.")
    return data

# Fetch Live Data
def fetch_live_data(ticker, interval):
    print(f"Fetching live data for {ticker} with {interval} interval...")
    data = yf.download(ticker, period="1d", interval=interval)
    if data.empty:
        print(f"No live data found for {ticker}.")
        return None
    print(f"Live data fetched successfully for {ticker}.")
    return data

# Save Data to Local Directory
def save_data_to_csv(data, filename, directory):
    os.makedirs(directory, exist_ok=True)
    file_path = os.path.join(directory, filename)
    data.to_csv(file_path)
    print(f"Data saved to {file_path}")
    return file_path

# Upload Data to S3
def upload_to_s3(file_path, bucket_name, aws_access_key, aws_secret_key):
    s3 = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key
    )
    try:
        s3.upload_file(file_path, bucket_name, os.path.basename(file_path))
        print(f"File {file_path} uploaded to S3 bucket {bucket_name}.")
    except FileNotFoundError:
        print(f"File {file_path} not found.")
    except NoCredentialsError:
        print("AWS credentials not available.")

# Main Function
def main():
    config_path = "/Users/dev/Desktop/Programming/Devlopment/StockVisionAI/config/configs.json"  
    config = load_config(config_path)

    # Fetch Historical Data
    for ticker in config["stock_data"]["tickers"]:
        data = fetch_historical_data(
            ticker,
            config["stock_data"]["start_date"],
            config["stock_data"]["end_date"],
            config["stock_data"]["interval"]
        )
        if data is not None:
            file_path = save_data_to_csv(data, f"{ticker}_historical.csv", "../data")
            upload_to_s3(file_path, config["aws"]["s3_bucket_name"], config["aws"]["access_key"], config["aws"]["secret_key"])

    # Fetch Live Data
    for ticker in config["live_data"]["tickers"]:
        data = fetch_live_data(ticker, config["live_data"]["interval"])
        if data is not None:
            file_path = save_data_to_csv(data, f"{ticker}_live.csv", "../data")
            upload_to_s3(file_path, config["aws"]["s3_bucket_name"], config["aws"]["access_key"], config["aws"]["secret_key"])

if __name__ == "__main__":
    main()
