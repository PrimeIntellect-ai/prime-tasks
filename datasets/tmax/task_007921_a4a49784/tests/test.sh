#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import subprocess
from pathlib import Path

OUTPUT = Path("/home/user/processed_logs.csv")
INPUT = Path("/home/user/data/logs.csv")
PROJECT = Path("/home/user/log_pipeline")


def test_processed_logs_exists():
    """Check if the processed dataset exists."""
    assert os.path.isfile(OUTPUT), f"Output dataset {OUTPUT} does not exist"


def test_processed_logs_content():
    """Check if the processed dataset has the correct content."""
    assert os.path.isfile(OUTPUT), f"Output dataset {OUTPUT} does not exist"

    expected_rows = [
        {"id": "1", "safe_group_id": "100", "score": "0.2000"},
        {"id": "2", "safe_group_id": "-1", "score": "0.2000"},
        {"id": "3", "safe_group_id": "200", "score": "0.0000"},
        {"id": "4", "safe_group_id": "-1", "score": "-0.2000"},
        {"id": "5", "safe_group_id": "105", "score": "0.4000"},
    ]

    with open(OUTPUT, "r", newline="") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual.get("id") == expected["id"], f"Row {i+1}: expected id {expected['id']}, got {actual.get('id')}"
        assert actual.get("safe_group_id") == expected["safe_group_id"], f"Row {i+1}: expected safe_group_id {expected['safe_group_id']}, got {actual.get('safe_group_id')}"
        actual_score = actual.get("score")
        assert actual_score is not None, f"Row {i+1}: missing 'score' column"
        assert actual_score == expected["score"], f"Row {i+1}: expected score {expected['score']}, got {actual_score}"


def test_cargo_toml_ndarray():
    """Check if ndarray is configured in Cargo.toml."""
    cargo_toml_path = PROJECT / "Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"Cargo.toml does not exist at {cargo_toml_path}"
    content = cargo_toml_path.read_text()
    assert "ndarray" in content, "The 'ndarray' crate is not configured in Cargo.toml"


def run_pipeline():
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust pipeline failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert OUTPUT.is_file(), "Running the Rust pipeline did not create processed_logs.csv"


def inspect_implementation():
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    package = next((p for p in metadata["packages"] if Path(p["manifest_path"]) == PROJECT / "Cargo.toml"), None)
    assert package is not None, "Could not find the log_pipeline package"
    assert any(d.get("name") == "ndarray" for d in package.get("dependencies", [])), "ndarray is not an actual Cargo dependency"

    sources = list((PROJECT / "src").rglob("*.rs"))
    assert sources, "The Rust project has no source files"
    source = "\n".join(path.read_text() for path in sources)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)

    assert re.search(r"\bgroup_id\s*:\s*Option\s*<\s*i32\s*>", source), "group_id is not declared as Option<i32>"
    assert re.search(r"\.dot\s*\(", source), "The regression score is not computed with ndarray's dot operation"
    assert re.search(r"\b(?:Array|Array1|arr1|array)\b\s*!?", source), "No ndarray array construction was found"


def read_output():
    with open(OUTPUT, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "safe_group_id", "score"], f"Incorrect output header: {reader.fieldnames}"
        return list(reader)


def test_complete_pipeline_behavior():
    # Preserve all original assertions before exercising the implementation.
    test_processed_logs_exists()
    test_processed_logs_content()
    test_cargo_toml_ndarray()
    inspect_implementation()

    original_input = INPUT.read_bytes()
    rng = random.SystemRandom()
    rows = [
        (7001, None, "XxxyYz!!"),
        (7002, 2147483647, "no matching letters"),
        (7003, -2147483648, "ZZzxy"),
    ]
    alphabet = "abcXYZxyz!? 012"
    for i in range(9):
        length = rng.randint(7, 41)
        content = "".join(rng.choice(alphabet) for _ in range(length))
        group_id = None if i % 3 == 0 else rng.randint(-100000, 100000)
        rows.append((7100 + i, group_id, content))

    try:
        with open(INPUT, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "group_id", "content"])
            for row_id, group_id, content in rows:
                writer.writerow([row_id, "" if group_id is None else group_id, content])

        if OUTPUT.exists():
            OUTPUT.unlink()
        run_pipeline()
        first_bytes = OUTPUT.read_bytes()
        actual = read_output()

        assert len(actual) == len(rows), f"Expected {len(rows)} dynamically generated rows, got {len(actual)}"
        for index, (record, (row_id, group_id, content)) in enumerate(zip(actual, rows), 1):
            assert record["id"] == str(row_id), f"Dynamic row {index} has incorrect id"
            expected_group = -1 if group_id is None else group_id
            assert record["safe_group_id"] == str(expected_group), f"Dynamic row {index} has incorrect safe_group_id"
            score_text = record["score"]
            assert re.fullmatch(r"-?\d+\.\d{4}", score_text or ""), f"Dynamic row {index} score is not formatted to four decimal places: {score_text}"
            lower = content.lower()
            expected_score = (0.5 * lower.count("x") + 0.3 * lower.count("y") - 0.2 * lower.count("z")) / len(content)
            assert abs(float(score_text) - expected_score) <= 0.000051, f"Dynamic row {index} has incorrect score: expected {expected_score}, got {score_text}"

        run_pipeline()
        assert OUTPUT.read_bytes() == first_bytes, "Pipeline output is not deterministic"
    finally:
        INPUT.write_bytes(original_input)

    # Regenerate the required final artifact from the original input and retain
    # the original exact-content assertions.
    run_pipeline()
    test_processed_logs_exists()
    test_processed_logs_content()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
