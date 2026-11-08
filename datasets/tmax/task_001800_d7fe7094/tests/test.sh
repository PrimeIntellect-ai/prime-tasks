#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import uuid

SCRIPT_PATH = "/home/user/pipeline/run.sh"
RAW_DIR = "/home/user/raw_configs"
PROCESSED_DIR = "/home/user/processed_configs"
CSV_PATH = "/home/user/output/config_matrix.csv"


def run_pipeline(timeout=30):
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Pipeline script failed with exit code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_original_fixture_and_assertions():
    """Retain the original fixture checks and exact expected results."""
    assert os.path.isfile(SCRIPT_PATH), f"Master script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Master script {SCRIPT_PATH} is not executable."

    run_pipeline()

    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."
    files = set(os.listdir(PROCESSED_DIR))
    expected_files = {"alpha.txt", "beta.txt", "gamma.txt"}
    assert "delta.txt" not in files, "delta.txt should have been skipped due to ERROR_ key."
    assert expected_files.issubset(files), f"Missing expected processed files. Found: {files}"

    expected_alpha = ["CACHE_SIZE=1024", "DB_HOST=10.0.0.1", "DB_PORT=5432", "MAX_RETRIES=3"]
    expected_beta = ["CACHE_SIZE=2048", "DB_HOST=10.0.0.2", "DB_PORT=5432", "TIMEOUT=30"]
    expected_gamma = ["DB_HOST=10.0.0.3", "DB_PORT=5432", "MAX_RETRIES=5", "TIMEOUT=60"]

    def check_file(filename, expected_lines):
        filepath = os.path.join(PROCESSED_DIR, filename)
        with open(filepath, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines == expected_lines, (
            f"Content of {filename} is incorrect or not sorted properly.\n"
            f"Expected: {expected_lines}\nGot: {lines}"
        )

    check_file("alpha.txt", expected_alpha)
    check_file("beta.txt", expected_beta)
    check_file("gamma.txt", expected_gamma)

    assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} is missing."
    expected_csv_lines = [
        "KEY,alpha,beta,gamma",
        "CACHE_SIZE,1024,2048,",
        "DB_HOST,10.0.0.1,10.0.0.2,10.0.0.3",
        "DB_PORT,5432,5432,5432",
        "MAX_RETRIES,3,,5",
        "TIMEOUT,,30,60",
    ]
    with open(CSV_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_csv_lines, (
        f"CSV content does not match expected output.\n"
        f"Expected:\n{expected_csv_lines}\nGot:\n{actual_lines}"
    )


def test_parallel_orchestration_is_present():
    """Require one of the parallel mechanisms explicitly allowed by the task."""
    sources = []
    for root, _, files in os.walk("/home/user/pipeline"):
        for name in files:
            path = os.path.join(root, name)
            if not os.path.isfile(path):
                continue
            try:
                with open(path, "r", errors="ignore") as f:
                    sources.append(f.read())
            except OSError:
                pass

    source = "\n".join(sources)
    source = "\n".join(line.split("#", 1)[0] for line in source.splitlines())
    uses_xargs_parallel = re.search(r"\bxargs\b[^\n]*(?:-P(?:\s*\d+)?|--max-procs(?:=|\s))", source)
    uses_gnu_parallel = re.search(r"(?:^|[;&|]\s*)parallel(?:\s|$)", source, re.MULTILINE)
    uses_background_wait = (
        re.search(r"(?<!&)&\s*$", source, re.MULTILINE)
        and re.search(r"(?:^|[;&]\s*)wait(?:\s|$)", source, re.MULTILINE)
    )
    assert uses_xargs_parallel or uses_gnu_parallel or uses_background_wait, (
        "No required parallel orchestration was found; use xargs -P, GNU parallel, "
        "or background jobs followed by wait."
    )


def test_pipeline_uses_current_inputs_and_derives_outputs():
    """Replace the fixed fixture with unpredictable TXT/JSON inputs and verify ETL behavior."""
    token = uuid.uuid4().hex[:10]
    dynamic_key = f"FEATURE_{token.upper()}"

    valid = {
        f"aardvark_{token}": {
            "format": "txt",
            "data": {
                "DB_HOST": f"host-a-{token}",
                "ALPHA_ONLY": f"a-{token}",
                dynamic_key: f"enabled-{token}",
            },
        },
        f"middle_{token}": {
            "format": "json",
            "data": {
                "DB_HOST": f"host-m-{token}",
                "JSON_ONLY": f"json-{token}",
                "SHARED_PORT": "8123",
            },
        },
        f"zebra_{token}": {
            "format": "txt",
            "data": {
                "DB_HOST": f"host-z-{token}",
                "SHARED_PORT": "9456",
                "ZETA_ONLY": f"z-{token}",
            },
        },
        f"jsonextra_{token}": {
            "format": "json",
            "data": {
                "ALPHA_ONLY": f"other-{token}",
                dynamic_key: f"disabled-{token}",
            },
        },
    }
    invalid = {
        f"badtext_{token}": ("txt", {
            "DB_HOST": f"bad-t-{token}",
            "ERROR_STATE": "1",
            "WOULD_LEAK": f"text-{token}",
        }),
        f"badjson_{token}": ("json", {
            "DB_HOST": f"bad-j-{token}",
            "ERROR_CORRUPT": "true",
            "WOULD_LEAK": f"json-{token}",
        }),
    }

    shutil.rmtree(RAW_DIR, ignore_errors=True)
    os.makedirs(RAW_DIR)

    for server, spec in valid.items():
        server_dir = os.path.join(RAW_DIR, server)
        os.makedirs(server_dir)
        if spec["format"] == "json":
            with open(os.path.join(server_dir, "config.json"), "w") as f:
                json.dump(spec["data"], f)
        else:
            # Deliberately write keys in reverse order so normalization must sort them.
            with open(os.path.join(server_dir, "config.txt"), "w") as f:
                for key in sorted(spec["data"], reverse=True):
                    f.write(f"{key}={spec['data'][key]}\n")

    for server, (fmt, data) in invalid.items():
        server_dir = os.path.join(RAW_DIR, server)
        os.makedirs(server_dir)
        if fmt == "json":
            with open(os.path.join(server_dir, "config.json"), "w") as f:
                json.dump(data, f)
        else:
            with open(os.path.join(server_dir, "config.txt"), "w") as f:
                for key in sorted(data, reverse=True):
                    f.write(f"{key}={data[key]}\n")

    # A correct rerunnable pipeline must not merge or retain stale processed data.
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    with open(os.path.join(PROCESSED_DIR, "stale_server.txt"), "w") as f:
        f.write("STALE_KEY=must_not_survive\n")
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w") as f:
        f.write("hardcoded,old,output\n")

    run_pipeline()

    expected_files = {f"{server}.txt" for server in valid}
    actual_files = set(os.listdir(PROCESSED_DIR))
    assert actual_files == expected_files, (
        "Processed files must correspond exactly to the currently valid servers. "
        f"Expected {expected_files}, got {actual_files}"
    )

    for server, spec in valid.items():
        expected_lines = [f"{key}={spec['data'][key]}" for key in sorted(spec["data"])]
        with open(os.path.join(PROCESSED_DIR, f"{server}.txt"), "r") as f:
            actual_lines = f.read().splitlines()
        assert actual_lines == expected_lines, (
            f"Incorrect normalized output for {server}. "
            f"Expected {expected_lines}, got {actual_lines}"
        )

    servers = sorted(valid)
    keys = sorted({key for spec in valid.values() for key in spec["data"]})
    expected_csv = ["KEY," + ",".join(servers)]
    for key in keys:
        expected_csv.append(key + "," + ",".join(valid[s]["data"].get(key, "") for s in servers))

    assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} is missing."
    with open(CSV_PATH, "r") as f:
        actual_csv = f.read().splitlines()
    assert actual_csv == expected_csv, (
        "Dynamic CSV content is incorrect.\n"
        f"Expected: {expected_csv}\nGot: {actual_csv}"
    )
    assert all("WOULD_LEAK" not in line for line in actual_csv), (
        "Keys from invalid servers were included in the matrix."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
