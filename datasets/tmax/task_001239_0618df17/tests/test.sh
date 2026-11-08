#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import secrets
import subprocess

import pytest


RUN_SCRIPT = "/home/user/run.sh"
PIPELINE = "/home/user/pipeline.py"
PRODUCTS = "/home/user/products.csv"
STATS = "/home/user/category_stats.csv"
RECOMMENDATIONS = "/home/user/recommendations.txt"
CHECKSUMS = "/home/user/checksums.txt"


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    """Ensure the submitted run script and Python pipeline exist and execute."""
    assert os.path.exists(RUN_SCRIPT), f"{RUN_SCRIPT} does not exist."
    assert os.path.isfile(RUN_SCRIPT), f"{RUN_SCRIPT} is not a regular file."
    assert os.access(RUN_SCRIPT, os.X_OK), f"{RUN_SCRIPT} is not executable."
    assert os.path.exists(PIPELINE), f"{PIPELINE} does not exist."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a regular file."

    result = subprocess.run(
        [RUN_SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Execution of {RUN_SCRIPT} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_category_stats_csv():
    """Verify the output for the original supplied dataset."""
    assert os.path.exists(STATS), f"{STATS} does not exist."

    expected_lines = [
        "category,avg_price",
        "Electronics,45.99",
        "Hardware,5.25",
        "Tools,14.38",
    ]
    with open(STATS, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {STATS} do not match the expected output. "
        f"Expected: {expected_lines}, but got: {actual_lines}"
    )


def test_recommendations_txt():
    """Verify the recommendations for the original supplied dataset."""
    assert os.path.exists(RECOMMENDATIONS), f"{RECOMMENDATIONS} does not exist."

    expected_lines = ["P007", "P005", "P002"]
    with open(RECOMMENDATIONS, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {RECOMMENDATIONS} do not match the expected recommendations. "
        f"Expected: {expected_lines}, but got: {actual_lines}"
    )


def test_checksums_txt():
    """Verify checksums for the original supplied dataset."""
    assert os.path.exists(CHECKSUMS), f"{CHECKSUMS} does not exist."
    assert os.path.exists(STATS), f"{STATS} does not exist to compute checksum."
    assert os.path.exists(RECOMMENDATIONS), (
        f"{RECOMMENDATIONS} does not exist to compute checksum."
    )

    def compute_sha256(path):
        hasher = hashlib.sha256()
        with open(path, "rb") as f:
            hasher.update(f.read())
        return hasher.hexdigest()

    expected_cat_sha = compute_sha256(STATS)
    expected_rec_sha = compute_sha256(RECOMMENDATIONS)

    with open(CHECKSUMS, "r") as f:
        content = f.read()

    assert expected_cat_sha in content, (
        f"SHA-256 hash for category_stats.csv ({expected_cat_sha}) "
        f"was not found in {CHECKSUMS}."
    )
    assert expected_rec_sha in content, (
        f"SHA-256 hash for recommendations.txt ({expected_rec_sha}) "
        f"was not found in {CHECKSUMS}."
    )
    assert "category_stats.csv" in content, (
        f"Filename 'category_stats.csv' was not found in {CHECKSUMS}."
    )
    assert "recommendations.txt" in content, (
        f"Filename 'recommendations.txt' was not found in {CHECKSUMS}."
    )


def make_unseen_dataset():
    suffix = secrets.token_hex(4).upper()
    categories = [f"Alpha_{suffix}", f"Middle_{suffix}", f"Zulu_{suffix}"]
    ids = sorted({"P" + secrets.token_hex(5).upper() for _ in range(8)})
    while len(ids) < 8 or "P001" in ids:
        ids = sorted({"P" + secrets.token_hex(5).upper() for _ in range(8)})

    rows = [
        ["P001", "Target", categories[1], "$11.11", "alpha beta gamma delta"],
        [ids[0], "Exact", categories[0], "$10.25", "alpha beta gamma delta"],
        [ids[1], "Close", categories[0], "$20.35", "alpha beta gamma"],
        [ids[2], "Tie One", categories[2], "$5.55", "alpha beta extra"],
        [ids[3], "Tie Two", categories[2], "$8.85", "alpha beta other"],
        [ids[4], "Weak", categories[1], "$17.77", "alpha"],
        [ids[5], "Punctuation", categories[1], "$22.21", "alpha, beta gamma"],
        [ids[6], "Invalid", categories[0], "invalid", "alpha beta gamma delta"],
        [ids[7], "Missing", categories[2], "", "alpha beta gamma delta"],
    ]
    return rows


def write_dataset(rows):
    with open(PRODUCTS, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "name", "category", "price", "description"])
        writer.writerows(rows)


def derive_expected_from_products():
    cleaned = []
    with open(PRODUCTS, newline="") as f:
        for row in csv.DictReader(f):
            try:
                price = float(row["price"].replace("$", ""))
            except (TypeError, ValueError):
                continue
            cleaned.append((row, price))

    grouped = {}
    for row, price in cleaned:
        grouped.setdefault(row["category"], []).append(price)
    expected_stats = [
        [category, f"{sum(grouped[category]) / len(grouped[category]):.2f}"]
        for category in sorted(grouped)
    ]

    target = next(row for row, _ in cleaned if row["id"] == "P001")
    target_words = set(target["description"].lower().split())
    scored = []
    for row, _ in cleaned:
        if row["id"] == "P001":
            continue
        words = set(row["description"].lower().split())
        union = target_words | words
        similarity = len(target_words & words) / len(union) if union else 0.0
        scored.append((row["id"], similarity))
    scored.sort(key=lambda item: (-item[1], item[0]))
    return expected_stats, [product_id for product_id, _ in scored[:3]]


def assert_generated_outputs():
    expected_stats, expected_recommendations = derive_expected_from_products()

    assert os.path.exists(STATS), f"{STATS} does not exist."
    with open(STATS, newline="") as f:
        rows = list(csv.reader(f))
    assert rows == [["category", "avg_price"]] + expected_stats, (
        f"Unexpected aggregate output: {rows}"
    )

    assert os.path.exists(RECOMMENDATIONS), f"{RECOMMENDATIONS} does not exist."
    with open(RECOMMENDATIONS) as f:
        recommendations = [line.strip() for line in f if line.strip()]
    assert recommendations == expected_recommendations, (
        f"Expected recommendations {expected_recommendations}, got {recommendations}"
    )


def assert_current_checksums():
    assert os.path.exists(CHECKSUMS), f"{CHECKSUMS} does not exist."
    with open(STATS, "rb") as f:
        stats_hash = hashlib.sha256(f.read()).hexdigest()
    with open(RECOMMENDATIONS, "rb") as f:
        rec_hash = hashlib.sha256(f.read()).hexdigest()
    with open(CHECKSUMS) as f:
        content = f.read()
    assert stats_hash in content
    assert rec_hash in content
    assert "category_stats.csv" in content
    assert "recommendations.txt" in content


def test_pipeline_on_unseen_inputs():
    """Execute pipeline.py itself and run.sh on runtime-generated datasets."""
    with open(PRODUCTS, "rb") as f:
        original_products = f.read()

    try:
        # First prove that pipeline.py itself performs the requested processing.
        write_dataset(make_unseen_dataset())
        for path in (STATS, RECOMMENDATIONS, CHECKSUMS):
            if os.path.exists(path):
                os.remove(path)
        direct = subprocess.run(
            ["python3", PIPELINE], cwd="/home/user", capture_output=True, text=True
        )
        assert direct.returncode == 0, (
            f"Execution of {PIPELINE} failed.\nStdout: {direct.stdout}\n"
            f"Stderr: {direct.stderr}"
        )
        assert_generated_outputs()

        # A different unseen dataset ensures run.sh regenerates, rather than reuses,
        # the Python pipeline's prior outputs and then creates valid checksums.
        write_dataset(make_unseen_dataset())
        for path in (STATS, RECOMMENDATIONS, CHECKSUMS):
            if os.path.exists(path):
                os.remove(path)
        via_run = subprocess.run(
            [RUN_SCRIPT], cwd="/home/user", capture_output=True, text=True
        )
        assert via_run.returncode == 0, (
            f"Execution of {RUN_SCRIPT} failed.\nStdout: {via_run.stdout}\n"
            f"Stderr: {via_run.stderr}"
        )
        assert_generated_outputs()
        assert_current_checksums()
    finally:
        with open(PRODUCTS, "wb") as f:
            f.write(original_products)
        subprocess.run([RUN_SCRIPT], cwd="/home/user", capture_output=True, text=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
