#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import csv
import stat
import secrets
from decimal import Decimal
import pytest


def test_venv_and_pandas_installed():
    """Test that the virtual environment exists and pandas is installed inside it."""
    python_bin = "/home/user/venv/bin/python"
    assert os.path.isfile(python_bin), f"Virtual environment Python binary not found at {python_bin}"

    try:
        subprocess.run(
            [python_bin, "-c", "import pandas"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to import pandas in the virtual environment. Error: {e.stderr}")


def test_aggregated_tax_csv():
    """Test that aggregated_tax.csv exists and contains the correct aggregated data."""
    csv_path = "/home/user/output/aggregated_tax.csv"
    assert os.path.isfile(csv_path), f"Output CSV not found at {csv_path}"

    expected_data = {
        "East": 45.0,
        "North": 25.0,
        "South": 40.0
    }

    actual_data = {}
    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "CSV file is empty"
        assert [h.strip() for h in header] == ["region_name", "total_tax"], \
            f"CSV header is incorrect. Expected ['region_name', 'total_tax'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Row does not have exactly 2 columns: {row}"
            region, tax_str = row[0].strip(), row[1].strip()
            try:
                tax = float(tax_str)
            except ValueError:
                pytest.fail(f"Cannot parse total_tax value '{tax_str}' as float for region '{region}'")
            actual_data[region] = tax

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} regions in output, found {len(actual_data)}"

    for region, expected_tax in expected_data.items():
        assert region in actual_data, f"Region '{region}' missing from output CSV"
        assert abs(actual_data[region] - expected_tax) < 1e-6, \
            f"Incorrect total_tax for {region}. Expected {expected_tax}, got {actual_data[region]}"


def test_experiment_log_json():
    """Test that experiment_log.json exists and contains the correct metrics."""
    json_path = "/home/user/experiment_log.json"
    assert os.path.isfile(json_path), f"Experiment log JSON not found at {json_path}"

    with open(json_path, "r") as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON")

    expected_keys = {"total_sales_rows", "valid_joined_rows", "max_tax_region"}
    actual_keys = set(log_data.keys())
    assert actual_keys == expected_keys, \
        f"JSON keys mismatch. Expected {expected_keys}, got {actual_keys}"

    assert log_data["total_sales_rows"] == 5, \
        f"Incorrect total_sales_rows. Expected 5, got {log_data['total_sales_rows']}"
    assert log_data["valid_joined_rows"] == 4, \
        f"Incorrect valid_joined_rows. Expected 4, got {log_data['valid_joined_rows']}"
    assert log_data["max_tax_region"] == "East", \
        f"Incorrect max_tax_region. Expected 'East', got '{log_data['max_tax_region']}'"


def _derive_expected(sales_path, customers_path, regions_path):
    with open(sales_path, newline="") as f:
        sales = list(csv.DictReader(f))
    with open(customers_path, newline="") as f:
        customers = list(csv.DictReader(f))
    with open(regions_path, newline="") as f:
        regions = list(csv.DictReader(f))

    customers_by_id = {row["customer_id"]: row for row in customers}
    regions_by_id = {row["region_id"]: row for row in regions}
    totals = {}
    joined_rows = 0
    for sale in sales:
        customer = customers_by_id.get(sale["customer_id"])
        if customer is None:
            continue
        region = regions_by_id.get(customer["region_id"])
        if region is None:
            continue
        joined_rows += 1
        name = region["region_name"]
        tax = Decimal(sale["amount"]) * Decimal(region["tax_rate"])
        totals[name] = totals.get(name, Decimal("0")) + tax

    assert totals, "Verifier's generated test data unexpectedly produced no joined rows"
    max_region = max(totals, key=totals.get)
    return len(sales), joined_rows, totals, max_region


def test_pipeline_exists_and_processes_changed_sources():
    """Execute the submitted pipeline on fresh inputs and verify derived results."""
    pipeline_path = "/home/user/pipeline.py"
    assert os.path.lexists(pipeline_path), f"Pipeline script not found at {pipeline_path}"
    mode = os.lstat(pipeline_path).st_mode
    assert stat.S_ISREG(mode), f"Pipeline path is not a regular file: {pipeline_path}"
    assert os.path.getsize(pipeline_path) > 0, "Pipeline script is empty"

    python_bin = "/home/user/venv/bin/python"
    paths = {
        "sales": "/home/user/data/sales.csv",
        "customers": "/home/user/data/customers.csv",
        "regions": "/home/user/data/regions.csv",
        "output": "/home/user/output/aggregated_tax.csv",
        "log": "/home/user/experiment_log.json",
    }
    backups = {}
    for path in paths.values():
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = secrets.token_hex(8)
    west = f"West_{token}"
    central = f"Central_{token}"
    sales_text = f"""transaction_id,customer_id,amount
{token}a,u1_{token},100
{token}b,u2_{token},40
{token}c,u1_{token},50
{token}d,u3_{token},-20
{token}e,missing_{token},999
{token}f,u4_{token},7
"""
    customers_text = f"""customer_id,region_id
u1_{token},z1_{token}
u2_{token},z2_{token}
u3_{token},z1_{token}
u4_{token},z9_{token}
"""
    regions_text = f"""region_id,region_name,tax_rate
z1_{token},{west},0.10
z2_{token},{central},0.20
"""

    try:
        with open(paths["sales"], "w", newline="") as f:
            f.write(sales_text)
        with open(paths["customers"], "w", newline="") as f:
            f.write(customers_text)
        with open(paths["regions"], "w", newline="") as f:
            f.write(regions_text)

        expected_sales, expected_joined, expected_totals, expected_max = _derive_expected(
            paths["sales"], paths["customers"], paths["regions"]
        )

        for generated in (paths["output"], paths["log"]):
            if os.path.exists(generated):
                os.remove(generated)

        try:
            result = subprocess.run(
                [python_bin, pipeline_path],
                cwd="/home/user",
                check=True,
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("pipeline.py did not finish within 30 seconds")
        except subprocess.CalledProcessError as e:
            pytest.fail(
                f"pipeline.py failed with exit code {e.returncode}. "
                f"stdout: {e.stdout}\nstderr: {e.stderr}"
            )

        assert os.path.isfile(paths["output"]), "pipeline.py did not generate aggregated_tax.csv"
        with open(paths["output"], newline="") as f:
            rows = list(csv.reader(f))
        assert rows, "Generated aggregated_tax.csv is empty"
        assert rows[0] == ["region_name", "total_tax"], \
            f"Generated CSV must have exactly the columns region_name,total_tax; got {rows[0]}"

        actual_totals = {}
        for row in rows[1:]:
            assert len(row) == 2, f"Generated CSV row does not have exactly two columns: {row}"
            region = row[0]
            assert region not in actual_totals, f"Duplicate region in generated CSV: {region}"
            try:
                actual_totals[region] = Decimal(row[1])
            except Exception:
                pytest.fail(f"Invalid total_tax value in generated CSV: {row[1]!r}")

        assert set(actual_totals) == set(expected_totals), \
            f"Generated regions differ from expected regions: {set(actual_totals)} vs {set(expected_totals)}"
        for region, expected in expected_totals.items():
            assert abs(actual_totals[region] - expected) < Decimal("0.000001"), \
                f"Incorrect dynamically generated total for {region}: expected {expected}, got {actual_totals[region]}"

        assert os.path.isfile(paths["log"]), "pipeline.py did not generate experiment_log.json"
        try:
            with open(paths["log"]) as f:
                log_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Generated experiment_log.json is invalid JSON: {e}")

        assert set(log_data) == {"total_sales_rows", "valid_joined_rows", "max_tax_region"}, \
            f"Generated JSON has incorrect keys: {set(log_data)}"
        assert type(log_data["total_sales_rows"]) is int, "total_sales_rows must be an integer"
        assert type(log_data["valid_joined_rows"]) is int, "valid_joined_rows must be an integer"
        assert type(log_data["max_tax_region"]) is str, "max_tax_region must be a string"
        assert log_data["total_sales_rows"] == expected_sales
        assert log_data["valid_joined_rows"] == expected_joined
        assert log_data["max_tax_region"] == expected_max
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
