#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/build_profile.py"
OUTPUT_PATH = "/home/user/final_profile.json"
CUSTOMERS_PATH = "/app/data/customers.csv"
INTERACTIONS_PATH = "/app/data/interactions.csv"
PURCHASES_PATH = "/app/data/purchases.json"


def load_output():
    assert os.path.exists(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")


def assert_strict_schema(data):
    assert isinstance(data, dict)
    assert set(data) == {
        "customer_id",
        "average_resolution_time",
        "target_category_spend",
        "unique_issues",
    }
    assert isinstance(data["customer_id"], str)
    assert type(data["average_resolution_time"]) is float
    assert type(data["target_category_spend"]) is float
    assert isinstance(data["unique_issues"], list)
    assert all(isinstance(issue, str) for issue in data["unique_issues"])


def test_final_profile_accuracy():
    data = load_output()
    score = 0.0

    # Check customer_id
    if data.get("customer_id") == "CUST-8924":
        score += 0.25

    # Check average_resolution_time
    avg_res_time = data.get("average_resolution_time", 0)
    if isinstance(avg_res_time, (int, float)) and abs(avg_res_time - 18.25) < 0.1:
        score += 0.25

    # Check target_category_spend
    spend = data.get("target_category_spend", 0)
    if isinstance(spend, (int, float)) and abs(spend - 400.0) < 0.1:
        score += 0.25

    # Check unique_issues
    issues = data.get("unique_issues", [])
    if isinstance(issues, list) and set(issues) == {"Defect", "Billing"}:
        score += 0.25

    assert score >= 1.0, f"Accuracy score {score} is below the threshold of 1.0. Parsed data: {data}"


def command_variants(customer_id, category):
    base = ["python3", SCRIPT_PATH]
    return [
        (base + [customer_id, category], None, None),
        (base + ["--customer-id", customer_id, "--category", category], None, None),
        (base + ["--customer-id", customer_id, "--product-category", category], None, None),
        (base + ["--customer_ref", customer_id, "--product_category", category], None, None),
        (base + ["--customer-ref", customer_id, "--category", category], None, None),
        (base, {
            "CUSTOMER_ID": customer_id,
            "CUSTOMER_REF": customer_id,
            "PRODUCT_CATEGORY": category,
            "CATEGORY": category,
        }, None),
        (base, None, customer_id + "\n" + category + "\n"),
    ]


def run_script(customer_id, category, variant_index=None):
    variants = command_variants(customer_id, category)
    indexes = [variant_index] if variant_index is not None else range(len(variants))
    failures = []

    for index in indexes:
        command, extra_env, stdin_text = variants[index]
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        env = os.environ.copy()
        if extra_env:
            env.update(extra_env)
        try:
            result = subprocess.run(
                command,
                cwd="/home/user",
                env=env,
                input=stdin_text,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"variant {index}: timed out")
            continue

        if result.returncode == 0 and os.path.isfile(OUTPUT_PATH):
            return index, load_output()
        failures.append(
            f"variant {index}: exit={result.returncode}, stdout={result.stdout[-300:]!r}, stderr={result.stderr[-300:]!r}"
        )

    pytest.fail("build_profile.py did not accept the parameterized inputs and create final_profile.json. " + " | ".join(failures))


def test_script_execution_parameterization_and_aggregation():
    assert os.path.isfile(SCRIPT_PATH), f"Required Python script missing at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be an actual Python source file"
    with open(SCRIPT_PATH, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    assert source.strip(), f"{SCRIPT_PATH} is empty"
    try:
        ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python source: {exc}")

    originals = {
        CUSTOMERS_PATH: open(CUSTOMERS_PATH, "rb").read(),
        INTERACTIONS_PATH: open(INTERACTIONS_PATH, "rb").read(),
        PURCHASES_PATH: open(PURCHASES_PATH, "rb").read(),
    }

    variant_index = None
    try:
        # Execute the submitted artifact for the ID and category transcribed from the supplied call.
        variant_index, actual = run_script("CUST-8924", "Electronics")
        assert_strict_schema(actual)
        test_final_profile_accuracy()

        # Replace the records with unpredictable data and exercise the same parameter interface.
        while True:
            customer_id = f"CUST-{secrets.randbelow(10000):04d}"
            if customer_id not in {"CUST-8924", "CUST-1111"}:
                break
        category = "Home Audio " + secrets.token_hex(3)
        issue_a = "Setup-" + secrets.token_hex(3)
        issue_b = "Returns-" + secrets.token_hex(3)
        time_a = 7.125 + secrets.randbelow(20)
        time_b = 31.875 + secrets.randbelow(20)
        price_a = 83.25 + secrets.randbelow(50)
        price_b = 146.75 + secrets.randbelow(50)

        with open(CUSTOMERS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["customer_id", "name", "region"])
            writer.writerow([customer_id, "Dynamic Customer", "Test Region"])
            writer.writerow(["CUST-0000", "Decoy Customer", "Elsewhere"])

        with open(INTERACTIONS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["ticket_id", "customer_id", "issue_type", "resolution_time"])
            writer.writerow(["D-1", customer_id, issue_a, time_a])
            writer.writerow(["D-2", customer_id, issue_b, time_b])
            writer.writerow(["D-3", customer_id, issue_a, time_a])
            writer.writerow(["D-X", "CUST-0000", "DecoyIssue", 999.0])

        records = [
            {
                "customer_ref": customer_id,
                "items": [
                    {"category": category, "price": price_a},
                    {"category": "Unrelated", "price": 9000.0},
                ],
                "transaction_metadata": {"date": "2026-01-01"},
            },
            {
                "customer_ref": customer_id,
                "items": [{"category": category, "price": price_b}],
                "transaction_metadata": {"date": "2026-01-02"},
            },
            {
                "customer_ref": "CUST-0000",
                "items": [{"category": category, "price": 8000.0}],
                "transaction_metadata": {"date": "2026-01-03"},
            },
        ]
        with open(PURCHASES_PATH, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        _, dynamic = run_script(customer_id, category, variant_index)
        assert_strict_schema(dynamic)
        assert dynamic["customer_id"] == customer_id
        assert abs(dynamic["average_resolution_time"] - ((time_a + time_b + time_a) / 3.0)) < 1e-8
        assert abs(dynamic["target_category_spend"] - (price_a + price_b)) < 1e-8
        assert set(dynamic["unique_issues"]) == {issue_a, issue_b}
        assert len(dynamic["unique_issues"]) == 2
    finally:
        for path, contents in originals.items():
            with open(path, "wb") as f:
                f.write(contents)

    # Leave the required final artifact populated for the supplied production inputs.
    _, restored = run_script("CUST-8924", "Electronics", variant_index)
    assert_strict_schema(restored)
    test_final_profile_accuracy()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
