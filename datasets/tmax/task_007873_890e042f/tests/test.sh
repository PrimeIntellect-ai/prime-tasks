#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_dataset_matcher.py
import csv
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/dataset_matcher"
DATASETS = "/home/user/datasets"
OUTPUT = "/home/user/recommendation.json"


def require_rust_project():
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), f"Missing Rust Cargo manifest: {manifest}"
    rust_sources = []
    for root, _, files in os.walk(PROJECT):
        for name in files:
            if name.endswith(".rs"):
                path = os.path.join(root, name)
                if os.path.isfile(path) and os.path.getsize(path) > 0:
                    rust_sources.append(path)
    assert rust_sources, "Cargo project contains no non-empty Rust source files."


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Rust program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f"File {OUTPUT} is not valid JSON: {e}")
    assert isinstance(data, dict), "Recommendation JSON must be an object."
    assert "most_similar_dataset" in data, "JSON missing 'most_similar_dataset' key."
    assert "cosine_similarity" in data, "JSON missing 'cosine_similarity' key."
    assert isinstance(data["cosine_similarity"], (int, float)) and not isinstance(data["cosine_similarity"], bool), \
        "Cosine similarity must be a number."
    assert math.isfinite(float(data["cosine_similarity"])), "Cosine similarity must be finite."
    return data


def parse_float(value):
    try:
        if value is None or value.strip() == "":
            return None
        number = float(value)
        return number if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def characteristic(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            sample_id = row.get("sample_id")
            if sample_id is None or sample_id == "":
                continue
            y = parse_float(row.get("yield"))
            assert y is not None, "Verifier fixtures always contain valid yield values."
            rows.append({
                "temp": parse_float(row.get("temp")),
                "pressure": parse_float(row.get("pressure")),
                "yield": y,
            })

    assert rows, f"No usable rows in verifier fixture {path}"
    for column in ("temp", "pressure"):
        valid = [r[column] for r in rows if r[column] is not None]
        assert valid, f"No valid values for {column} in verifier fixture {path}"
        mean = sum(valid) / len(valid)
        for row in rows:
            if row[column] is None:
                row[column] = mean

    yield_mean = sum(r["yield"] for r in rows) / len(rows)
    variance = sum((r["yield"] - yield_mean) ** 2 for r in rows) / len(rows)
    stddev = math.sqrt(variance)
    if stddev != 0.0:
        rows = [r for r in rows if abs((r["yield"] - yield_mean) / stddev) <= 2.0]
    assert rows, f"All rows were removed from verifier fixture {path}"
    return [sum(r[c] for r in rows) / len(rows) for c in ("temp", "pressure", "yield")]


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(x * x for x in b))
    return dot / (na * nb)


def expected_recommendation():
    query = characteristic(os.path.join(DATASETS, "query.csv"))
    candidates = []
    for name in os.listdir(DATASETS):
        if name.endswith(".csv") and name != "query.csv":
            candidates.append((cosine(query, characteristic(os.path.join(DATASETS, name))), name))
    assert candidates, "No candidate CSV files found."
    similarity, name = max(candidates, key=lambda item: item[0])
    return name, round(similarity, 4)


def assert_matches_oracle(data):
    expected_name, expected_similarity = expected_recommendation()
    assert data["most_similar_dataset"] == expected_name, (
        f"Expected most similar dataset to be '{expected_name}', "
        f"but got '{data['most_similar_dataset']}'."
    )
    actual = float(data["cosine_similarity"])
    assert abs(actual - expected_similarity) < 0.0000001, (
        f"Expected rounded cosine similarity {expected_similarity:.4f}, but got {actual}."
    )
    assert actual == round(actual, 4), "Cosine similarity was not rounded to 4 decimal places."


def write_csv(name, rows):
    with open(os.path.join(DATASETS, name), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_id", "temp", "pressure", "yield"])
        writer.writerows(rows)


def install_dynamic_fixture():
    for name in os.listdir(DATASETS):
        path = os.path.join(DATASETS, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

    token = secrets.token_hex(6)
    good = f"zz_cleaned_{token}.csv"
    decoy = f"aa_decoy_{token}.csv"
    far = f"far_{token}.csv"

    write_csv("query.csv", [
        ["Q1", "19.9", "10.99", "50"],
        ["Q2", "19.9", "10.99", "50"],
        ["Q3", "19.9", "10.99", "50"],
    ])
    write_csv(decoy, [
        ["D1", "10", "1", "50"],
        ["D2", "10", "1", "50"],
        ["D3", "10", "1", "50"],
    ])

    good_rows = [[f"G{i}", "10", "1", "50"] for i in range(1, 10)]
    good_rows.append(["G10", "not-a-number", "", "50"])
    good_rows.append(["G11", "1000", "1000", "1000"])
    good_rows.append(["", "99999", "99999", "50"])
    write_csv(good, good_rows)
    write_csv(far, [
        ["F1", "1000", "1", "1"],
        ["F2", "1000", "1", "1"],
        ["F3", "1000", "1", "1"],
    ])
    return good


def main():
    require_rust_project()

    # Preserve all assertions made by the original verifier, but only after
    # deleting the pre-existing JSON and actually running the Rust program.
    original = run_program()
    assert original["most_similar_dataset"] == "gamma.csv", (
        f"Expected most similar dataset to be 'gamma.csv', but got "
        f"'{original['most_similar_dataset']}'."
    )
    original_similarity = float(original["cosine_similarity"])
    assert 0.9990 <= original_similarity <= 1.0000, (
        f"Cosine similarity {original_similarity} is out of expected bounds (0.9990 to 1.0000)."
    )
    assert_matches_oracle(original)

    backup_parent = tempfile.mkdtemp(prefix="dataset-verifier-")
    backup = os.path.join(backup_parent, "datasets")
    shutil.copytree(DATASETS, backup)
    try:
        expected_good = install_dynamic_fixture()
        dynamic = run_program()
        assert_matches_oracle(dynamic)
        assert dynamic["most_similar_dataset"] == expected_good
    finally:
        shutil.rmtree(DATASETS, ignore_errors=True)
        shutil.copytree(backup, DATASETS)
        shutil.rmtree(backup_parent, ignore_errors=True)

    # Leave the requested artifact consistent with the restored original inputs.
    final = run_program()
    assert final["most_similar_dataset"] == "gamma.csv"
    assert 0.9990 <= float(final["cosine_similarity"]) <= 1.0000
    assert_matches_oracle(final)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_dataset_matcher.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
