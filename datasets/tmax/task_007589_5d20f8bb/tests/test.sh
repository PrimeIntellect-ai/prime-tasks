#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

PROGRAM = "/home/user/aggregate.go"
OUTPUT = "/home/user/output.json"
DATA_DIR = "/home/user/data"


def compute_expected():
    products = {}
    with open(os.path.join(DATA_DIR, "products.csv"), "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            products[row["product_id"]] = row["category"]

    regions = {}
    with open(os.path.join(DATA_DIR, "regions.csv"), "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            regions[row["region_id"]] = row["country"]

    agg = {}
    with open(os.path.join(DATA_DIR, "sales.csv"), "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            amount = float(row["amount"])
            if amount < 50.00:
                continue
            key = (products[row["product_id"]], regions[row["region_id"]])
            if key not in agg:
                agg[key] = {"total_revenue": 0.0, "transaction_count": 0}
            agg[key]["total_revenue"] += amount
            agg[key]["transaction_count"] += 1

    expected_results = []
    for (cat, country), metrics in agg.items():
        expected_results.append({
            "category": cat,
            "country": country,
            "total_revenue": round(metrics["total_revenue"], 2),
            "transaction_count": metrics["transaction_count"]
        })
    expected_results.sort(key=lambda x: (-x["total_revenue"], x["country"]))
    return expected_results


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    try:
        result = subprocess.run(
            ["go", "run", PROGRAM],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Go program timed out.")
    assert result.returncode == 0, (
        "go run /home/user/aggregate.go failed:\n" + result.stdout + result.stderr
    )


def assert_output_correct(expected_results):
    assert os.path.isfile(OUTPUT), "Output file /home/user/output.json does not exist."
    with open(OUTPUT, "r") as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            assert False, "Output file /home/user/output.json is not valid JSON."

    assert isinstance(actual_results, list), "Output JSON must be an array of objects."
    assert len(actual_results) == len(expected_results), \
        f"Expected {len(expected_results)} records, found {len(actual_results)}."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert isinstance(actual, dict), f"Record {i} must be an object."
        assert "category" in actual, f"Record {i} is missing 'category'."
        assert "country" in actual, f"Record {i} is missing 'country'."
        assert "total_revenue" in actual, f"Record {i} is missing 'total_revenue'."
        assert "transaction_count" in actual, f"Record {i} is missing 'transaction_count'."
        assert actual["category"] == expected["category"], \
            f"Record {i} category mismatch: expected {expected['category']}, got {actual['category']}."
        assert actual["country"] == expected["country"], \
            f"Record {i} country mismatch: expected {expected['country']}, got {actual['country']}."
        try:
            actual_rev = float(actual["total_revenue"])
        except (TypeError, ValueError):
            pytest.fail(f"Record {i} total_revenue is not numeric.")
        assert abs(actual_rev - expected["total_revenue"]) < 0.01, \
            f"Record {i} total_revenue mismatch: expected {expected['total_revenue']}, got {actual_rev}."
        assert actual["transaction_count"] == expected["transaction_count"], \
            f"Record {i} transaction_count mismatch: expected {expected['transaction_count']}, got {actual['transaction_count']}."


@pytest.fixture(scope="session")
def original_run():
    assert os.path.isfile(PROGRAM), "Go program /home/user/aggregate.go does not exist or is not a regular file."
    expected = compute_expected()
    run_program()
    return expected


def test_output_json_exists(original_run):
    assert os.path.isfile(OUTPUT), "Output file /home/user/output.json does not exist."


def test_output_json_correctness(original_run):
    assert_output_correct(original_run)


def test_program_processes_runtime_csv_inputs(original_run):
    token = secrets.token_hex(6)
    product_base = 10000 + secrets.randbelow(50000)
    region_base = 70000 + secrets.randbelow(20000)
    category_a = "RuntimeCategory_" + token
    category_b = "OtherCategory_" + token
    country_a = "AlphaCountry_" + token
    country_b = "ZuluCountry_" + token

    total_cents = 20000 + secrets.randbelow(30000)
    first_cents = 5000 + secrets.randbelow(total_cents - 10000)
    second_cents = total_cents - first_cents
    larger_cents = total_cents + 10000 + secrets.randbelow(20000)

    with open(os.path.join(DATA_DIR, "products.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["product_id", "category", "name", "price"])
        writer.writerow([product_base, category_a, "Runtime One", "10.00"])
        writer.writerow([product_base + 1, category_a, "Runtime Two", "20.00"])
        writer.writerow([product_base + 2, category_b, "Runtime Three", "30.00"])

    with open(os.path.join(DATA_DIR, "regions.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["region_id", "country", "city"])
        writer.writerow([region_base, country_a, "City A"])
        writer.writerow([region_base + 1, country_b, "City B"])

    def money(cents):
        return f"{cents // 100}.{cents % 100:02d}"

    with open(os.path.join(DATA_DIR, "sales.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sale_id", "product_id", "region_id", "amount", "timestamp"])
        writer.writerow([1, product_base, region_base, money(first_cents), "2026-01-01T00:00:00Z"])
        writer.writerow([2, product_base + 1, region_base, money(second_cents), "2026-01-02T00:00:00Z"])
        writer.writerow([3, product_base, region_base + 1, money(total_cents), "2026-01-03T00:00:00Z"])
        writer.writerow([4, product_base + 2, region_base, money(larger_cents), "2026-01-04T00:00:00Z"])
        writer.writerow([5, product_base + 2, region_base + 1, "49.99", "2026-01-05T00:00:00Z"])

    expected = compute_expected()
    run_program()
    assert_output_correct(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
