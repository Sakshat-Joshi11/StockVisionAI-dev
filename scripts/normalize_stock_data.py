import sys
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.sql.functions import col

# Initialize Glue context and job
args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = glueContext.create_dynamic_frame.from_catalog(
    database="partitioned_stock_data",  # Replace with your database name
    table_name="partitioned_raw_partitioned_raw"  # Replace with your table name
)

# Convert to Spark DataFrame for transformations
df = job.toDF()

# Handle column ambiguity by renaming partitions and resolving duplicates
# Drop original 'date' column if it exists to avoid conflicts
if "date" in df.columns:
    df = df.drop("date")

# Rename partition columns to meaningful names
df_renamed = (
    df
    .withColumnRenamed("partition_0", "ticker")
    .withColumnRenamed("partition_1", "year")
    .withColumnRenamed("partition_2", "month")
    .withColumnRenamed("partition_3", "date")
)

# Data Cleaning: Normalize column types
df_cleaned = (
    df_renamed
    .withColumn("returns", col("returns").cast("double"))
    .withColumn("RSI", col("RSI").cast("double"))
    .withColumn("MACD", col("MACD").cast("double"))
    .withColumn("MACD_Signal", col("MACD_Signal").cast("double"))
    .withColumn("Rolling_Volatility", col("Rolling_Volatility").cast("double"))
    .na.fill({
        "returns": 0.0,
        "RSI": 50.0,
        "MACD": 0.0,
        "MACD_Signal": 0.0,
        "Rolling_Volatility": 0.0
    })
)

# Write the cleaned data back to S3 in Parquet format, preserving partitions
output_path = "s3://stock-market-raw-data-dev/cleaned_partitioned_data/"
(
    df_cleaned
    .write
    .partitionBy("ticker", "year", "month", "date")  # Use renamed columns for partitioning
    .mode("overwrite")
    .parquet(output_path)
)

print(f"Cleaned data written to {output_path}")
