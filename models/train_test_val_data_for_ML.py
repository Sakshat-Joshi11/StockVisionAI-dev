import boto3
import pandas as pd
from sklearn.model_selection import train_test_split

# Step 1: Download Dataset
s3 = boto3.client('s3')
bucket_name = 'stock-market-raw-data-dev'
object_key = 'curated_data/4d2bb800-bf34-460a-9ad7-fa5bfaa457f1.csv'
local_file_path = '/Users/dev/Desktop/Programming/Devlopment/StockVisionAI/models/dataset.csv'
s3.download_file(bucket_name, object_key, local_file_path)
print("Dataset downloaded successfully.")

# Step 2: Split Dataset
df = pd.read_csv(local_file_path)
train, temp = train_test_split(df, test_size=0.3, random_state=42)
val, test = train_test_split(temp, test_size=0.5, random_state=42)
train.to_csv('train.csv', index=False)
val.to_csv('val.csv', index=False)
test.to_csv('test.csv', index=False)
print("Dataset split and saved locally.")

# Step 3: Upload Splits Back to S3
train_key = 's3://stock-market-raw-data-dev/curated_data/train//train.csv'
val_key = 's3://stock-market-raw-data-dev/curated_data/val//val.csv'
test_key = 's3://stock-market-raw-data-dev/curated_data/test//test.csv'
s3.upload_file('train.csv', bucket_name, train_key)
s3.upload_file('val.csv', bucket_name, val_key)
s3.upload_file('test.csv', bucket_name, test_key)
print("Split datasets uploaded to S3.")
