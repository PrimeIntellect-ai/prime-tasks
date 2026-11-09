#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import subprocess
from pathlib import Path


def test_script_exists_and_executable():
    script_path = "/home/user/prepare_data.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_dataset_output():
    dataset_path = "/home/user/dataset_run_baseline.csv"
    assert os.path.isfile(dataset_path), f"Dataset file {dataset_path} does not exist."

    expected_data = [
        ["method", "status", "url_len", "param_count", "suspicious", "tokenized_url"],
        ["GET", "200", "11", "0", "0", "index html"],
        ["POST", "401", "30", "2", "0", "login php user admin pass 123"],
        ["GET", "403", "35", "1", "1", "search q script alert 1 script"],
        ["GET", "200", "39", "2", "1", "api data id 1 token base64 encoded str"],
        ["PUT", "201", "16", "0", "0", "upload test txt"]
    ]

    with open(dataset_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_data = list(reader)

    assert actual_data == expected_data, f"Content of {dataset_path} does not match expected output. Got: {actual_data}"


def test_experiment_log_output():
    log_path = "/home/user/experiment_log.csv"
    assert os.path.isfile(log_path), f"Experiment log file {log_path} does not exist."

    expected_data = [
        ["experiment_id", "total_rows", "suspicious_count"],
        ["run_baseline", "5", "2"]
    ]

    with open(log_path, "r", newline="") as f:
        reader = csv.reader(f)
        actual_data = list(reader)

    assert actual_data == expected_data, f"Content of {log_path} does not match expected output. Got: {actual_data}"


def test_script_processes_fresh_fixture_and_experiment_id():
    script_path = Path("/home/user/prepare_data.sh")
    raw_path = Path("/home/user/raw_access.log")
    log_path = Path("/home/user/experiment_log.csv")
    experiment_id = "verify_" + secrets.token_hex(8)
    dataset_path = Path(f"/home/user/dataset_{experiment_id}.csv")
    nonce = secrets.token_hex(6)

    records = [
        ("GET", f"/MiXeD/EvAl?x=1&y=={nonce}", "418"),
        ("POST", f"/plain---Path/{nonce}?empty=", "207"),
        ("PATCH", f"/A%2Fb/BaSe64SCRIPT?q={nonce}+z", "503"),
        ("HEAD", "/", "204"),
    ]
    raw_lines = [
        f'203.0.113.{i} - - [11/Sep/2026:12:00:0{i} +0000] "{method} {url} HTTP/1.1" {status} {100+i}'
        for i, (method, url, status) in enumerate(records, 1)
    ]

    expected_dataset = [["method", "status", "url_len", "param_count", "suspicious", "tokenized_url"]]
    suspicious_count = 0
    for method, url, status in records:
        suspicious = int(any(term in url.lower() for term in ("eval", "base64", "script")))
        suspicious_count += suspicious
        tokenized = re.sub(r"[^A-Za-z0-9]+", " ", url).strip().lower()
        expected_dataset.append([
            method,
            status,
            str(len(url)),
            str(url.count("=")),
            str(suspicious),
            tokenized,
        ])

    raw_backup = raw_path.read_bytes()
    log_existed = log_path.exists()
    log_backup = log_path.read_bytes() if log_existed else None
    dataset_existed = dataset_path.exists()
    dataset_backup = dataset_path.read_bytes() if dataset_existed else None

    try:
        with log_path.open("r", newline="") as f:
            prior_log = list(csv.reader(f))

        raw_path.write_text("\n".join(raw_lines) + "\n")
        if dataset_path.exists():
            dataset_path.unlink()

        subprocess.run(
            [str(script_path), experiment_id],
            cwd="/home/user",
            check=True,
            timeout=15,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        assert dataset_path.is_file(), f"Script did not create {dataset_path}"
        with dataset_path.open("r", newline="") as f:
            actual_dataset = list(csv.reader(f))
        with log_path.open("r", newline="") as f:
            actual_log = list(csv.reader(f))

        assert actual_dataset == expected_dataset, (
            f"Fresh-fixture dataset does not match expected output. Got: {actual_dataset}"
        )
        expected_log = prior_log + [[experiment_id, str(len(records)), str(suspicious_count)]]
        assert actual_log == expected_log, (
            f"Experiment log was not appended correctly. Got: {actual_log}"
        )
    finally:
        raw_path.write_bytes(raw_backup)
        if log_existed:
            log_path.write_bytes(log_backup)
        elif log_path.exists():
            log_path.unlink()
        if dataset_existed:
            dataset_path.write_bytes(dataset_backup)
        elif dataset_path.exists():
            dataset_path.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
