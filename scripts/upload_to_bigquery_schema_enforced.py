"""
Kupferkanne – Bulk Upload to BigQuery (Schema-Enforced Raw Load)
================================================================
Uploads all CSV files (dimensions + monthly orders/items) to BigQuery.

Key design choice:
  - Monthly fact shards (orders20YYMM, items20YYMM) are loaded with an
    EXPLICIT and CONSISTENT raw schema so wildcard queries remain usable.
  - Raw fact columns are intentionally loaded as STRING, not DATE/NUMERIC,
    to preserve malformed source values for downstream auditing and cleaning.
    This keeps the raw layer faithful to source files while preventing schema
    drift between monthly shards.

Why this matters:
  - BigQuery wildcard tables require schema compatibility across all matched
    tables. If one monthly shard lands with OrderDate=DATE and another with
    OrderDate=STRING, wildcard queries can fail before SAFE_CAST is applied.
  - Loading all monthly fact shards with a fixed STRING-based raw schema makes
    wildcard queries stable and keeps data-quality issues visible to SQL audit
    scripts instead of rejecting rows during ingestion.

Dimensions:
  - Dimension tables remain autodetected by default. They are single tables,
    so wildcard compatibility is not a concern there.

Retention:
  - The warehouse keeps its tables between pipeline runs, so a dataset created
    here is given no default table or partition expiration.

Usage:
  python upload_to_bigquery_schema_enforced.py
  python upload_to_bigquery_schema_enforced.py --data-dir ./data --project kupferkanne-2026
  python upload_to_bigquery_schema_enforced.py --purge-existing-monthly
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import time
from typing import Iterable, Optional

from google.api_core.exceptions import NotFound
from google.cloud import bigquery


# ---------------------------------------------------------------------------
# Explicit raw schemas for monthly wildcard tables
# ---------------------------------------------------------------------------
# These are intentionally STRING-based to preserve dirty raw values for the
# audit/cleaning pipeline while guaranteeing schema consistency across shards.
ORDER_RAW_SCHEMA = [
    bigquery.SchemaField("OrderID", "STRING"),
    bigquery.SchemaField("CustomerID", "STRING"),
    bigquery.SchemaField("OrderDate", "STRING"),
    bigquery.SchemaField("OrderDiscountPct", "STRING"),
    bigquery.SchemaField("BasketItemCount", "STRING"),
]

ITEM_RAW_SCHEMA = [
    bigquery.SchemaField("OrderID", "STRING"),
    bigquery.SchemaField("LineNumber", "STRING"),
    bigquery.SchemaField("ProductID", "STRING"),
    bigquery.SchemaField("Quantity", "STRING"),
    bigquery.SchemaField("UnitPrice", "STRING"),
    bigquery.SchemaField("LineNetAmount", "STRING"),
]

MONTHLY_ORDERS_RE = re.compile(r"^orders\d{6}\.csv$", re.IGNORECASE)
MONTHLY_ITEMS_RE = re.compile(r"^items\d{6}\.csv$", re.IGNORECASE)
MONTHLY_TABLE_RE = re.compile(r"^(orders|items)\d{6}$", re.IGNORECASE)


def resolve_input_layout(data_dir: str) -> tuple[str, str]:
    """Resolve where dimension and monthly files actually live.

    Supports both:
      1. data_dir/dimensions + data_dir/monthly
      2. all CSVs directly inside data_dir
    """
    dimensions_dir = os.path.join(data_dir, "dimensions")
    monthly_dir = os.path.join(data_dir, "monthly")

    has_nested_dimensions = os.path.isdir(dimensions_dir)
    has_nested_monthly = os.path.isdir(monthly_dir)

    resolved_dimensions_dir = dimensions_dir if has_nested_dimensions else data_dir
    resolved_monthly_dir = monthly_dir if has_nested_monthly else data_dir
    return resolved_dimensions_dir, resolved_monthly_dir


def ensure_dataset(client: bigquery.Client, dataset_ref: str, location: str) -> None:
    """Create dataset if needed, with no default table or partition expiration."""
    try:
        dataset = client.get_dataset(dataset_ref)
        print(f"Dataset {dataset_ref} already exists.")
        if (
            dataset.default_table_expiration_ms
            or dataset.default_partition_expiration_ms
        ):
            print(
                f"  [WARN] {dataset_ref} carries a default expiration; "
                "tables loaded here are deleted when it elapses."
            )
    except NotFound:
        dataset = bigquery.Dataset(dataset_ref)
        dataset.location = location
        dataset.default_table_expiration_ms = None
        dataset.default_partition_expiration_ms = None
        client.create_dataset(dataset, exists_ok=True)
        print(f"Created dataset {dataset_ref} in {location}")


def purge_existing_monthly_tables(client: bigquery.Client, dataset_ref: str) -> int:
    """Delete existing monthly orders/items shards before reload.

    This is useful when reloading the entire raw layer from scratch to avoid
    leaving behind old shards that still match wildcard patterns.
    """
    deleted = 0
    for table in client.list_tables(dataset_ref):
        if MONTHLY_TABLE_RE.match(table.table_id):
            client.delete_table(f"{dataset_ref}.{table.table_id}", not_found_ok=True)
            deleted += 1
    return deleted


def validate_expected_schema(
    table: bigquery.Table,
    expected_schema: Iterable[bigquery.SchemaField],
) -> None:
    """Raise if the loaded table schema differs from the expected schema."""
    actual = [(field.name, field.field_type) for field in table.schema]
    expected = [(field.name, field.field_type) for field in expected_schema]
    if actual != expected:
        raise ValueError(
            f"Schema mismatch for {table.full_table_id}.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )


def upload_csv(
    client: bigquery.Client,
    filepath: str,
    table_id: str,
    *,
    skip_leading_rows: int = 1,
    schema: Optional[list[bigquery.SchemaField]] = None,
    autodetect: bool = False,
) -> int:
    """Upload a single CSV file to BigQuery.

    When schema is supplied, autodetect must stay False so the target schema is
    fully deterministic.
    """
    if schema is not None and autodetect:
        raise ValueError("Cannot use both explicit schema and autodetect=True.")

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=skip_leading_rows,
        autodetect=autodetect,
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )

    with open(filepath, "rb") as f:
        job = client.load_table_from_file(f, table_id, job_config=job_config)

    job.result()
    table = client.get_table(table_id)
    if schema is not None:
        validate_expected_schema(table, schema)
    return table.num_rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upload Kupferkanne CSVs to BigQuery with schema enforcement for monthly fact tables."
    )
    parser.add_argument(
        "--data-dir",
        default=r".\data",
        help="Root directory containing dimensions/ and monthly/ folders",
    )
    parser.add_argument(
        "--project",
        default="kupferkanne-2026",
        help="BigQuery project ID",
    )
    parser.add_argument(
        "--dataset",
        default="sales",
        help="BigQuery dataset name",
    )
    parser.add_argument(
        "--location",
        default="EU",
        help="BigQuery dataset location, e.g. EU or US",
    )
    parser.add_argument(
        "--purge-existing-monthly",
        action="store_true",
        help="Delete existing orders20YYMM/items20YYMM tables in the dataset before upload.",
    )
    args = parser.parse_args()

    data_dir = os.path.abspath(args.data_dir)
    dim_dir, monthly_dir = resolve_input_layout(data_dir)
    dataset_ref = f"{args.project}.{args.dataset}"
    client = bigquery.Client(project=args.project)

    print(f"Using data directory: {data_dir}")
    print(f"Resolved dimensions directory: {dim_dir}")
    print(f"Resolved monthly directory: {monthly_dir}")
    print(f"Target dataset: {dataset_ref}")

    ensure_dataset(client, dataset_ref, args.location)

    if args.purge_existing_monthly:
        deleted = purge_existing_monthly_tables(client, dataset_ref)
        print(f"Purged {deleted} existing monthly wildcard tables from {dataset_ref}")

    # -----------------------------------------------------------------------
    # PHASE 1: Upload dimensions
    # -----------------------------------------------------------------------
    print("\n=== UPLOADING DIMENSIONS ===")
    dim_files = {
        "dim_customers": os.path.join(dim_dir, "dim_customers.csv"),
        "dim_products": os.path.join(dim_dir, "dim_products.csv"),
    }

    for table_name, filepath in dim_files.items():
        if not os.path.exists(filepath):
            print(f"  SKIP: {filepath} not found")
            continue
        table_id = f"{dataset_ref}.{table_name}"
        rows = upload_csv(client, filepath, table_id, autodetect=True)
        print(f"  [OK] {table_name}: {rows:,} rows loaded (autodetect)")

    # -----------------------------------------------------------------------
    # PHASE 2: Upload monthly order files with enforced schema
    # -----------------------------------------------------------------------
    print("\n=== UPLOADING ORDERS (schema-enforced raw) ===")
    order_files = sorted(
        fp
        for fp in glob.glob(os.path.join(monthly_dir, "orders*.csv"))
        if MONTHLY_ORDERS_RE.match(os.path.basename(fp))
    )
    print(f"  Found {len(order_files)} order files")

    total_order_rows = 0
    for filepath in order_files:
        filename = os.path.basename(filepath).replace(".csv", "")
        table_id = f"{dataset_ref}.{filename}"
        rows = upload_csv(client, filepath, table_id, schema=ORDER_RAW_SCHEMA)
        total_order_rows += rows
        print(f"  [OK] {filename}: {rows:,} rows loaded with fixed raw schema")

    print(f"  TOTAL ORDER ROWS: {total_order_rows:,}")

    # -----------------------------------------------------------------------
    # PHASE 3: Upload monthly item files with enforced schema
    # -----------------------------------------------------------------------
    print("\n=== UPLOADING ITEMS (schema-enforced raw) ===")
    item_files = sorted(
        fp
        for fp in glob.glob(os.path.join(monthly_dir, "items*.csv"))
        if MONTHLY_ITEMS_RE.match(os.path.basename(fp))
    )
    print(f"  Found {len(item_files)} item files")

    total_item_rows = 0
    for filepath in item_files:
        filename = os.path.basename(filepath).replace(".csv", "")
        table_id = f"{dataset_ref}.{filename}"
        rows = upload_csv(client, filepath, table_id, schema=ITEM_RAW_SCHEMA)
        total_item_rows += rows
        print(f"  [OK] {filename}: {rows:,} rows loaded with fixed raw schema")

    print(f"  TOTAL ITEM ROWS: {total_item_rows:,}")

    # -----------------------------------------------------------------------
    # SUMMARY
    # -----------------------------------------------------------------------
    print("\n" + "=" * 60)
    print("UPLOAD COMPLETE")
    print("=" * 60)
    print("  Dimensions:  2 tables")
    print(f"  Orders:      {len(order_files)} tables ({total_order_rows:,} rows)")
    print(f"  Items:       {len(item_files)} tables ({total_item_rows:,} rows)")
    print(f"  Total:       {2 + len(order_files) + len(item_files)} tables")
    print(f"\n  Dataset: {dataset_ref}")
    print("  Raw monthly schemas are now wildcard-safe and cast-friendly for SQL.")
    print("\n  Next step: run sql/00_0_data_quality_audit_raw_kupferkanne_2026.sql in BigQuery Console")


if __name__ == "__main__":
    start = time.time()
    main()
    elapsed = time.time() - start
    print(f"\n  Elapsed: {elapsed:.1f} seconds")
