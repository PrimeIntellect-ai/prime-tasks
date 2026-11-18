#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import subprocess

import pytest

INVENTORY = "/home/user/inventory.csv"
PIPELINE = "/home/user/run_pipeline.sh"
CLEANED = "/home/user/cleaned_inventory.jsonl"
BEST = "/home/user/best_match.txt"
QUERY = "Heavy duty industrial steel storage rack"

EXPECTED_INPUT = [
    ["1", "Lightweight Aluminum Chair", "45.0", "5.0", "2.0", "2.0", "3.0"],
    ["2", "Heavy Duty Steel Shelving Unit", "150.0", "80.0", "4.0", "2.0", "6.0"],
    ["3", "Plastic Storage Bin", "15.0", "2.0", "1.5", "1.5", "1.5"],
    ["4", "Oak Wood Dining Table", "", "60.0", "6.0", "3.0", "2.5"],
    ["5", "Industrial Warehouse Rack", "250.0", "", "8.0", "3.0", "10.0"],
    ["6", "Cardboard Box Small", "2.0", "0.5", "1.0", "1.0", "1.0"],
    ["7", "Lead Block Anomaly", "500.0", "5000.0", "1.0", "1.0", "1.0"],
    ["8", "Aerogel Sample", "1000.0", "0.001", "2.0", "2.0", "2.0"],
    ["9", "Broken Item", "10.0", "5.0", "", "2.0", "2.0"],
    ["10", "Standard Office Desk", "120.0", "40.0", "5.0", "2.5", "2.5"],
]


def read_and_validate_input():
    with open(INVENTORY, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    assert header == ["id", "product_name", "price", "weight", "length", "width", "height"]
    assert rows == EXPECTED_INPUT, "The supplied inventory.csv must not be modified"


def compute_expected():
    with open(INVENTORY, newline="") as f:
        raw_data = list(csv.DictReader(f))

    clean_data = [
        dict(row) for row in raw_data
        if row["length"] != "" and row["width"] != "" and row["height"] != ""
    ]

    prices = sorted(float(row["price"]) for row in clean_data if row["price"] != "")
    n = len(prices)
    median_price = ((prices[n // 2 - 1] + prices[n // 2]) / 2.0
                    if n % 2 == 0 else prices[n // 2])
    weights = [float(row["weight"]) for row in clean_data if row["weight"] != ""]
    mean_weight = sum(weights) / len(weights)

    for row in clean_data:
        row["id"] = int(row["id"])
        row["price"] = float(row["price"]) if row["price"] != "" else median_price
        row["weight"] = float(row["weight"]) if row["weight"] != "" else mean_weight
        row["length"] = float(row["length"])
        row["width"] = float(row["width"])
        row["height"] = float(row["height"])
        row["volume"] = row["length"] * row["width"] * row["height"]
        row["density"] = row["weight"] / row["volume"]

    densities = [row["density"] for row in clean_data]
    mean_density = sum(densities) / len(densities)
    variance = sum((value - mean_density) ** 2 for value in densities) / (len(densities) - 1)
    std_density = math.sqrt(variance)

    remaining = []
    for row in clean_data:
        z_score = (row["density"] - mean_density) / std_density
        if abs(z_score) <= 2.0:
            remaining.append(row)
    return remaining, median_price, mean_weight


@pytest.fixture(scope="module", autouse=True)
def execute_pipeline():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist or is not a file"
    read_and_validate_input()
    original_input = open(INVENTORY, "rb").read()
    for path in (CLEANED, BEST):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ["bash", PIPELINE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=900,
    )
    assert result.returncode == 0, f"Pipeline failed with exit code {result.returncode}:\n{result.stdout}"
    assert open(INVENTORY, "rb").read() == original_input, "Pipeline modified inventory.csv"


def test_cleaned_inventory_content():
    assert os.path.isfile(CLEANED), f"{CLEANED} does not exist"
    expected_rows, median_price, mean_weight = compute_expected()
    expected_by_id = {row["id"]: row for row in expected_rows}

    output_rows = []
    with open(CLEANED) as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except Exception as exc:
                pytest.fail(f"Invalid JSON on line {line_number}: {exc}")
            assert isinstance(record, dict), f"Line {line_number} is not a JSON object"
            output_rows.append(record)

    expected_columns = {
        "id", "product_name", "price", "weight", "length", "width", "height", "volume", "density"
    }
    assert len(output_rows) == len(expected_rows), "Unexpected number of output records"

    output_ids = []
    for record in output_rows:
        assert set(record) == expected_columns, (
            f"Record must contain exactly {sorted(expected_columns)}, got {sorted(record)}"
        )
        assert isinstance(record["id"], int) and not isinstance(record["id"], bool), "id must be an integer"
        output_ids.append(record["id"])

    assert len(output_ids) == len(set(output_ids)), "Output contains duplicate IDs"
    assert set(output_ids) == set(expected_by_id), (
        f"Expected IDs {set(expected_by_id)} after outlier removal, got {set(output_ids)}"
    )

    numeric_columns = ["price", "weight", "length", "width", "height", "volume", "density"]
    for record in output_rows:
        expected = expected_by_id[record["id"]]
        assert record["product_name"] == expected["product_name"]
        for column in numeric_columns:
            value = record[column]
            assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{column} must be numeric"
            assert math.isfinite(float(value)), f"{column} must be finite"
            assert math.isclose(float(value), expected[column], rel_tol=1e-6, abs_tol=1e-9), (
                f"Incorrect {column} for ID {record['id']}: expected {expected[column]}, got {value}"
            )

    # Preserve the original targeted imputation and engineering assertions.
    record4 = next(row for row in output_rows if row["id"] == 4)
    assert math.isclose(record4["price"], median_price, rel_tol=1e-5)
    record5 = next(row for row in output_rows if row["id"] == 5)
    assert math.isclose(record5["weight"], mean_weight, rel_tol=1e-5)
    assert math.isclose(record5["volume"], 8.0 * 3.0 * 10.0, rel_tol=1e-5)
    assert math.isclose(record5["density"], mean_weight / 240.0, rel_tol=1e-5)


def test_best_match_recomputed_with_required_model():
    assert os.path.isfile(BEST), f"{BEST} does not exist"
    content = open(BEST).read().strip()
    assert re.fullmatch(r"[0-9]+", content), "best_match.txt must contain only an integer ID"
    submitted_id = int(content)
    assert submitted_id in [2, 5], f"Expected best match ID to be 2 or 5, got {content}"

    expected_rows, _, _ = compute_expected()
    try:
        from sentence_transformers import SentenceTransformer
    except Exception as exc:
        pytest.fail(f"sentence-transformers is not installed or importable: {exc}")

    try:
        model = SentenceTransformer("all-MiniLM-L6-v2")
        texts = [row["product_name"] for row in expected_rows] + [QUERY]
        embeddings = model.encode(texts, normalize_embeddings=True, convert_to_numpy=True)
    except Exception as exc:
        pytest.fail(f"Could not load and run all-MiniLM-L6-v2: {exc}")

    query_embedding = embeddings[-1]
    product_embeddings = embeddings[:-1]
    similarities = product_embeddings @ query_embedding
    best_index = int(similarities.argmax())
    expected_id = expected_rows[best_index]["id"]
    assert submitted_id == expected_id, (
        f"Expected best match ID {expected_id} from all-MiniLM-L6-v2 cosine similarity, got {submitted_id}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
