#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import secrets
import string
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/anomaly_detector"
OUTPUT = "/home/user/corrected_queries.csv"


def compute_expected_stats(log_path):
    stats = {}
    if not os.path.exists(log_path):
        return stats

    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 2:
                continue

            qid = parts[0]
            val_str = parts[1]
            try:
                val = float(val_str)
            except ValueError:
                continue

            if qid not in stats:
                stats[qid] = {"count": 0.0, "mean": 0.0, "m2": 0.0}

            s = stats[qid]
            s["count"] += 1.0
            delta = val - s["mean"]
            s["mean"] += delta / s["count"]
            delta2 = val - s["mean"]
            s["m2"] += delta * delta2

    return stats


def test_corrected_queries_csv_exists():
    csv_path = OUTPUT
    assert os.path.isfile(csv_path), f"Expected output file not found at {csv_path}. Did the service run successfully?"


def test_corrected_queries_csv_content():
    csv_path = OUTPUT
    log_path = "/home/user/data/metrics.log"

    assert os.path.isfile(csv_path), "CSV file is missing."
    assert os.path.isfile(log_path), "Metrics log file is missing."

    expected_stats = compute_expected_stats(log_path)

    actual_stats = {}
    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["query_id", "count", "mean", "variance"], \
            f"CSV header is incorrect. Expected ['query_id', 'count', 'mean', 'variance'], got {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Invalid CSV row length: {row}"
            qid, count_str, mean_str, var_str = row
            actual_stats[qid] = {
                "count": float(count_str),
                "mean": float(mean_str),
                "variance": float(var_str)
            }

    expected_qids = set(expected_stats.keys())
    actual_qids = set(actual_stats.keys())

    assert expected_qids == actual_qids, \
        f"Mismatch in query IDs in CSV. Expected {expected_qids}, but got {actual_qids}. Ensure malformed rows are skipped and valid rows are processed."

    for qid in expected_qids:
        e_stat = expected_stats[qid]
        a_stat = actual_stats[qid]

        e_count = e_stat["count"]
        e_mean = e_stat["mean"]

        if e_count <= 1.0:
            e_var = 0.0
        else:
            e_var = e_stat["m2"] / (e_count - 1.0)

        expected_mean_rounded = round(e_mean, 2)
        expected_var_rounded = round(e_var, 2)

        assert math.isclose(a_stat["count"], e_count, rel_tol=1e-5), \
            f"Count mismatch for {qid}. Expected {e_count}, got {a_stat['count']}"
        assert math.isclose(a_stat["mean"], expected_mean_rounded, rel_tol=1e-2), \
            f"Mean mismatch for {qid}. Expected ~{expected_mean_rounded}, got {a_stat['mean']}"
        assert not math.isnan(a_stat["variance"]), \
            f"Variance for {qid} is NaN. Ensure division by zero is prevented."
        assert math.isclose(a_stat["variance"], expected_var_rounded, rel_tol=1e-2), \
            f"Variance mismatch for {qid}. Expected ~{expected_var_rounded}, got {a_stat['variance']}"


def test_service_executes_on_verifier_controlled_input():
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    main_rs = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.isfile(cargo_toml), "Rust package manifest is missing"
    assert os.path.isfile(main_rs), "Rust service source is missing"
    assert not os.path.islink(cargo_toml), "Cargo.toml must be a regular project file"
    assert not os.path.islink(main_rs), "src/main.rs must be a regular Rust source file"

    token = ''.join(secrets.choice(string.ascii_uppercase) for _ in range(12))
    qa = "RUNA_" + token
    qb = "RUNB_" + token
    qc = "RUNC_" + token
    bad1 = "BAD1_" + token
    bad2 = "BAD2_" + token
    base = secrets.randbelow(500) + 200

    lines = [
        f"{qa}|{base}.25",
        f"{qb}|{base + 17}.75",
        f"{qa}|{base + 4}.25",
        f"{bad1}|90.5e",
        f"{qa}|not-a-number",
        f"{qa}|{base - 3}.25",
        f"{qc}|1.25e2",
        f"{bad2}|1e+",
        "line-without-delimiter",
    ]

    with tempfile.TemporaryDirectory(prefix="anomaly-verifier-") as td:
        input_path = os.path.join(td, "metrics.log")
        with open(input_path, "w") as f:
            f.write("\n".join(lines) + "\n")

        expected = compute_expected_stats(input_path)
        try:
            os.remove(OUTPUT)
        except FileNotFoundError:
            pass

        result = subprocess.run(
            ["cargo", "run", "--release", "--", input_path],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )

    assert result.returncode == 0, \
        f"Fixed Rust service failed on malformed input. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(OUTPUT), "Running the service did not create corrected_queries.csv"

    actual = {}
    with open(OUTPUT, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["query_id", "count", "mean", "variance"]
        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Invalid CSV row: {row}"
            qid, count_s, mean_s, variance_s = row
            assert qid not in actual, f"Duplicate query row for {qid}"
            values = (float(count_s), float(mean_s), float(variance_s))
            assert all(math.isfinite(v) for v in values), f"Non-finite statistic for {qid}: {row}"
            actual[qid] = values

    assert set(actual) == set(expected), \
        f"Controlled run produced query IDs {set(actual)}, expected {set(expected)}; malformed rows must be skipped"
    assert bad1 not in actual and bad2 not in actual

    for qid, stat in expected.items():
        count, mean, variance = actual[qid]
        expected_variance = 0.0 if stat["count"] <= 1.0 else stat["m2"] / (stat["count"] - 1.0)
        assert math.isclose(count, stat["count"], rel_tol=0, abs_tol=1e-9)
        assert math.isclose(mean, stat["mean"], rel_tol=0, abs_tol=0.011), \
            f"Mean mismatch for {qid}: got {mean}, expected {stat['mean']}"
        assert math.isclose(variance, expected_variance, rel_tol=0, abs_tol=0.011), \
            f"Variance mismatch for {qid}: got {variance}, expected {expected_variance}"

    assert actual[qb][2] == 0.0, "A query with one data point must have variance 0.0"
    assert actual[qc][2] == 0.0, "A valid scientific-notation singleton must have variance 0.0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
