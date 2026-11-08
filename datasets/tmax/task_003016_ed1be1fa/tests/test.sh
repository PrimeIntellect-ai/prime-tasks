#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile

PROJECT_DIR = "/home/user/mlops_tracker"
MAIN_RS = os.path.join(PROJECT_DIR, "src", "main.rs")
SUMMARY_PATH = "/home/user/experiment_summary.json"
ARTIFACTS_DIR = "/home/user/model_artifacts"
CSV_PATH = "/home/user/inference_benchmarks.csv"


def rust_target():
    assert os.path.isfile(MAIN_RS), f"Rust source {MAIN_RS} is missing."
    assert os.path.getsize(MAIN_RS) > 0, f"Rust source {MAIN_RS} is empty."

    result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Cargo metadata failed:\n{result.stdout}\n{result.stderr}"
    metadata = json.loads(result.stdout)

    wanted = os.path.realpath(MAIN_RS)
    matches = []
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []) and os.path.realpath(target.get("src_path", "")) == wanted:
                matches.append((package["name"], target["name"]))

    assert matches, "Cargo does not define src/main.rs as an executable Rust target."
    return matches[0]


def run_rust(package_name, target_name):
    if os.path.lexists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--package", package_name, "--bin", target_name],
        cwd=PROJECT_DIR,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust program failed to compile or run:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(SUMMARY_PATH), f"File {SUMMARY_PATH} is missing. The Rust program must produce this file."


def expected_summary():
    expected_bytes = 0
    if os.path.isdir(ARTIFACTS_DIR):
        for root, _, files in os.walk(ARTIFACTS_DIR):
            for filename in files:
                expected_bytes += os.path.getsize(os.path.join(root, filename))

    expected_tokens = 0
    latencies = []
    if os.path.isfile(CSV_PATH):
        with open(CSV_PATH, "r", newline="", encoding="utf-8") as handle:
            reader = csv.reader(handle)
            next(reader, None)
            for row in reader:
                if len(row) >= 2:
                    expected_tokens += len(row[0].split())
                    try:
                        latencies.append(float(row[1]))
                    except ValueError:
                        pass

    n = len(latencies)
    if n > 0:
        sample_mean = sum(latencies) / n
        prior_mean = 50.0
        prior_var = 100.0
        like_var = 25.0
        inv_post_var = (1.0 / prior_var) + (n / like_var)
        post_var = 1.0 / inv_post_var
        posterior = post_var * ((prior_mean / prior_var) + (n * sample_mean / like_var))
        posterior = round(posterior, 2)
    else:
        posterior = 0.0

    return expected_bytes, expected_tokens, posterior


def assert_summary():
    expected_bytes, expected_tokens, expected_posterior = expected_summary()
    try:
        with open(SUMMARY_PATH, "r", encoding="utf-8") as handle:
            summary = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {SUMMARY_PATH} is not valid JSON: {exc}")

    assert "total_artifact_bytes" in summary, "Key 'total_artifact_bytes' is missing in the JSON file."
    assert summary["total_artifact_bytes"] == expected_bytes, \
        f"Expected total_artifact_bytes to be {expected_bytes}, got {summary['total_artifact_bytes']}."
    assert "total_tokens" in summary, "Key 'total_tokens' is missing in the JSON file."
    assert summary["total_tokens"] == expected_tokens, \
        f"Expected total_tokens to be {expected_tokens}, got {summary['total_tokens']}."
    assert "posterior_mean_latency" in summary, "Key 'posterior_mean_latency' is missing in the JSON file."
    assert summary["posterior_mean_latency"] == expected_posterior, \
        f"Expected posterior_mean_latency to be {expected_posterior}, got {summary['posterior_mean_latency']}."


def test_rust_program_generates_summary_for_actual_inputs():
    package_name, target_name = rust_target()

    # Preserve the original assertions while requiring the Rust target to create
    # the output itself.
    run_rust(package_name, target_name)
    assert_summary()

    backup_root = tempfile.mkdtemp(prefix="mlops_verifier_")
    backup_artifacts = os.path.join(backup_root, "model_artifacts")
    backup_csv = os.path.join(backup_root, "inference_benchmarks.csv")

    shutil.move(ARTIFACTS_DIR, backup_artifacts)
    shutil.move(CSV_PATH, backup_csv)
    try:
        os.makedirs(os.path.join(ARTIFACTS_DIR, "nested"))
        nonce = secrets.token_hex(6)
        sizes = [
            1000 + secrets.randbelow(4000),
            5000 + secrets.randbelow(4000),
            9000 + secrets.randbelow(4000),
        ]
        paths = [
            os.path.join(ARTIFACTS_DIR, f"weights_{nonce}.bin"),
            os.path.join(ARTIFACTS_DIR, "nested", f"config_{nonce}.dat"),
            os.path.join(ARTIFACTS_DIR, "nested", f"optimizer_{nonce}.bin"),
        ]
        for path, size in zip(paths, sizes):
            with open(path, "wb") as handle:
                handle.write(os.urandom(size))

        latencies = [20 + secrets.randbelow(61) for _ in range(4)]
        extra_words = 1 + secrets.randbelow(5)
        rows = [
            ["alpha beta", latencies[0]],
            ["gamma   delta epsilon", latencies[1]],
            ["tab\tseparated words", latencies[2]],
            [" ".join([f"token_{nonce}"] * extra_words), latencies[3]],
        ]
        with open(CSV_PATH, "w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(["text_sample", "latency_ms"])
            writer.writerows(rows)

        # These values are generated only at verification time, so a fixed JSON
        # writer cannot satisfy this run.
        run_rust(package_name, target_name)
        assert_summary()
    finally:
        if os.path.isdir(ARTIFACTS_DIR):
            shutil.rmtree(ARTIFACTS_DIR)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        shutil.move(backup_artifacts, ARTIFACTS_DIR)
        shutil.move(backup_csv, CSV_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)

    # Leave the requested output corresponding to the original environment.
    run_rust(package_name, target_name)
    assert_summary()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
