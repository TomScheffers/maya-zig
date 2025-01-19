import polars as pl

# df = pl.read_parquet("data/stock_current/org_key=0/file.parquet", hive_partitioning=False)
# df = df.with_columns(
#     txt=pl.lit("Hello World!"), 
#     txt2=pl.when(pl.col("economical") == 0).then(pl.lit(None)).otherwise(pl.col("economical").map_elements(lambda x: f"Stock equals {x}", return_dtype=str))
# )
# df.write_parquet("data/stock_current/org_key=0/file.parquet")
# print(df)
# print(df.schema)

import time

df = pl.scan_parquet("data/stock_current/org_key=0/file.parquet", hive_partitioning=False)
for col in df.columns:
    t1 = time.time()
    df = pl.scan_parquet("data/stock_current/org_key=0/file.parquet", hive_partitioning=False).select([col]).collect()
    print(col, time.time() - t1)

# df = pl.read_parquet("s3://thor-engine-dev/snowflake/tables/stock_current/data_*")

# df = df.cast({"ORG_KEY": pl.Int32, "STORE_KEY": pl.Int32, "SKU_KEY": pl.Int32}).rename(lambda x: x.lower())

# df.write_parquet("data/stock/data.parquet")