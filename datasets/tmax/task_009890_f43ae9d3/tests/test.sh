#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import random
import shutil
import stat
import subprocess

import pyarrow as pa
import pyarrow.parquet as pq
import pytest

SCRIPT_PATH = "/home/user/process_sales.py"
RAW_DIR = "/home/user/raw_data"
RATES_PATH = "/home/user/config/exchange_rates.json"
JSON_PATH = "/home/user/processed/summary.json"
PARQUET_PATH = "/home/user/processed/summary.parquet"

CANONICAL_RATES = {
    "USD": 1.0,
    "EUR": 1.1,
    "GBP": 1.25,
    "JPY": 0.007,
    "CAD": 0.75,
}
CATEGORIES = ["Electronics", "Clothing", "Home", "Sports", "Books"]
HEADER = ["order_id", "timestamp", "category", "price", "quantity", "currency"]


def validate_canonical_inputs():
    with open(RATES_PATH, "r") as f:
        assert json.load(f) == CANONICAL_RATES, "The exchange-rate input was modified"

    rng = random.Random(42)
    order_id = 1
    currencies = list(CANONICAL_RATES.keys())
    for chunk in range(20):
        path = f"{RAW_DIR}/sales_chunk_{chunk}.csv"
        assert os.path.isfile(path), f"Missing raw data file: {path}"
        with open(path, "r", newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        assert rows and rows[0] == HEADER, f"Invalid header in {path}"
        assert len(rows) == 501, f"Expected 500 data rows in {path}"
        expected_rows = []
        for _ in range(500):
            category = rng.choice(CATEGORIES)
            price = round(rng.uniform(5.0, 500.0), 2)
            quantity = rng.randint(1, 10)
            currency = rng.choice(currencies)
            expected_rows.append([
                f"ORD{order_id:05d}",
                "2023-10-01T12:00:00Z",
                category,
                str(price),
                str(quantity),
                currency,
            ])
            order_id += 1
        assert rows[1:] == expected_rows, f"Raw input data was modified: {path}"


def get_expected_data():
    rates_path = "/home/user/config/exchange_rates.json"
    assert os.path.isfile(rates_path), f"Missing exchange rates file: {rates_path}"

    with open(rates_path, "r") as f:
        rates = json.load(f)

    expected_agg = {}
    for chunk in range(20):
        csv_path = f"/home/user/raw_data/sales_chunk_{chunk}.csv"
        assert os.path.isfile(csv_path), f"Missing raw data file: {csv_path}"
        with open(csv_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat = row["category"]
                rev = float(row["price"]) * int(row["quantity"]) * rates[row["currency"]]
                qty = int(row["quantity"])
                if cat not in expected_agg:
                    expected_agg[cat] = {"total_revenue_usd": 0.0, "total_items": 0}
                expected_agg[cat]["total_revenue_usd"] += rev
                expected_agg[cat]["total_items"] += qty

    expected_list = []
    for cat, vals in expected_agg.items():
        expected_list.append({
            "category": cat,
            "total_revenue_usd": round(vals["total_revenue_usd"], 2),
            "total_items": vals["total_items"],
        })

    expected_list.sort(key=lambda x: (-x["total_revenue_usd"], x["category"]))
    return expected_list


def assert_parallel_approach(source):
    tree = ast.parse(source, filename=SCRIPT_PATH)
    imports = set()
    calls = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module.split(".")[0])
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.add(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.add(node.func.attr)

    executor_used = bool(calls & {"ThreadPoolExecutor", "ProcessPoolExecutor", "Pool"}) and bool(
        calls & {"map", "submit", "apply", "apply_async", "map_async", "imap", "imap_unordered"}
    )
    explicit_processes = "Process" in calls and "start" in calls and "join" in calls
    joblib_used = "joblib" in imports and "Parallel" in calls
    dask_used = "dask" in imports and "read_csv" in calls and bool(calls & {"compute", "persist"})
    ray_used = "ray" in imports and bool(calls & {"remote", "get"})
    assert executor_used or explicit_processes or joblib_used or dask_used or ray_used, (
        "process_sales.py must use a parallel processing API to read/process the CSV files"
    )


def run_script():
    shutil.rmtree("/home/user/processed", ignore_errors=True)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"process_sales.py failed:\n{result.stdout}"


def assert_outputs(expected):
    assert os.path.isfile(JSON_PATH), f"File missing: {JSON_PATH}"
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Invalid JSON in {JSON_PATH}: {exc}")
    assert isinstance(data, list)
    assert len(data) == len(expected)
    for actual, wanted in zip(data, expected):
        assert isinstance(actual, dict)
        assert set(actual) == {"category", "total_revenue_usd", "total_items"}
        assert actual["category"] == wanted["category"]
        assert type(actual["total_items"]) is int
        assert actual["total_items"] == wanted["total_items"]
        assert isinstance(actual["total_revenue_usd"], (int, float))
        assert math.isfinite(actual["total_revenue_usd"])
        assert abs(actual["total_revenue_usd"] - wanted["total_revenue_usd"]) < 1e-6

    assert os.path.isfile(PARQUET_PATH), f"File missing: {PARQUET_PATH}"
    table = pq.read_table(PARQUET_PATH)
    assert table.column_names == ["category", "total_revenue_usd", "total_items"]
    assert pa.types.is_string(table.schema.field("category").type)
    assert pa.types.is_floating(table.schema.field("total_revenue_usd").type)
    assert pa.types.is_integer(table.schema.field("total_items").type)
    parquet_data = table.to_pylist()
    assert len(parquet_data) == len(expected)
    for actual, wanted in zip(parquet_data, expected):
        assert actual["category"] == wanted["category"]
        assert actual["total_items"] == wanted["total_items"]
        assert math.isfinite(actual["total_revenue_usd"])
        assert abs(actual["total_revenue_usd"] - wanted["total_revenue_usd"]) < 1e-6


def snapshot_inputs():
    paths = [RATES_PATH] + [f"{RAW_DIR}/sales_chunk_{i}.csv" for i in range(20)]
    return {path: open(path, "rb").read() for path in paths}


def restore_inputs(snapshot):
    for path, contents in snapshot.items():
        with open(path, "wb") as f:
            f.write(contents)


def install_challenge_input():
    with open(RATES_PATH, "w") as f:
        json.dump({"USD": 1.0, "EUR": 1.37, "GBP": 0.91, "JPY": 0.011, "CAD": 0.64}, f)
    path = f"{RAW_DIR}/sales_chunk_0.csv"
    with open(path, "r", newline="") as f:
        rows = list(csv.reader(f))
    rows[1][2] = "ChallengeCategory"
    rows[1][3] = "987.65"
    rows[1][4] = "7"
    rows[1][5] = "EUR"
    rows[2][2] = "ChallengeCategory"
    rows[2][3] = "123.45"
    rows[2][4] = "3"
    rows[2][5] = "GBP"
    with open(path, "w", newline="") as f:
        csv.writer(f).writerows(rows)


def test_script_exists_uses_parallelism_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Not a regular file: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()
    assert source.strip(), "process_sales.py is empty"
    assert_parallel_approach(source)

    validate_canonical_inputs()
    canonical_snapshot = snapshot_inputs()

    try:
        install_challenge_input()
        challenge_snapshot = snapshot_inputs()
        challenge_expected = get_expected_data()
        run_script()
        assert snapshot_inputs() == challenge_snapshot, "The script modified its source inputs"
        assert_outputs(challenge_expected)
    finally:
        restore_inputs(canonical_snapshot)

    validate_canonical_inputs()
    canonical_expected = get_expected_data()
    run_script()
    validate_canonical_inputs()
    assert_outputs(canonical_expected)


def test_summary_json():
    json_path = "/home/user/processed/summary.json"
    assert os.path.isfile(json_path), f"File missing: {json_path}"

    with open(json_path, "r") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {json_path}")

    expected_data = get_expected_data()

    assert isinstance(agent_data, list), "JSON output should be a list of objects"
    assert len(agent_data) == len(expected_data), f"Expected {len(expected_data)} categories, got {len(agent_data)}"

    for exp, agt in zip(expected_data, agent_data):
        assert agt.get("category") == exp["category"], f"Expected category '{exp['category']}' at this position, got '{agt.get('category')}'"
        assert agt.get("total_items") == exp["total_items"], f"Incorrect total_items for category '{exp['category']}'"

        agt_revenue = agt.get("total_revenue_usd")
        assert agt_revenue is not None, f"Missing total_revenue_usd for category '{exp['category']}'"
        assert abs(agt_revenue - exp["total_revenue_usd"]) <= 0.1, f"Incorrect total_revenue_usd for category '{exp['category']}'. Expected {exp['total_revenue_usd']}, got {agt_revenue}"


def test_summary_parquet():
    parquet_path = "/home/user/processed/summary.parquet"
    assert os.path.isfile(parquet_path), f"File missing: {parquet_path}"

    with open(parquet_path, "rb") as f:
        header = f.read(4)
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)

    assert header == b"PAR1", f"Invalid Parquet file header in {parquet_path}"
    assert footer == b"PAR1", f"Invalid Parquet file footer in {parquet_path}"

    expected = get_expected_data()
    table = pq.read_table(parquet_path)
    assert table.column_names == ["category", "total_revenue_usd", "total_items"]
    assert pa.types.is_string(table.schema.field("category").type)
    assert pa.types.is_floating(table.schema.field("total_revenue_usd").type)
    assert pa.types.is_integer(table.schema.field("total_items").type)
    rows = table.to_pylist()
    assert len(rows) == len(expected)
    for actual, wanted in zip(rows, expected):
        assert actual["category"] == wanted["category"]
        assert actual["total_items"] == wanted["total_items"]
        assert abs(actual["total_revenue_usd"] - wanted["total_revenue_usd"]) < 1e-6
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
