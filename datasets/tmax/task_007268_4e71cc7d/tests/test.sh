#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import subprocess

BINARY = "/tmp/cleaner_verifier_bin"
BAD_METRIC = "SRE_CORRUPT_0x8F9A"


def test_bad_metric_txt():
    path = "/home/user/bad_metric.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "SRE_CORRUPT_0x8F9A", f"Incorrect content in {path}: {content}"


def test_cleaned_metrics_log():
    path = "/home/user/cleaned_metrics.log"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "2023-10-12T10:00:00Z,OK,METRIC_NODE_A_001\n"
        "2023-10-12T10:00:05Z,OK,METRIC_NODE_B_002\n"
        "2023-10-12T10:00:10Z,WARN,METRIC_NODE_C_003\n"
        "2023-10-12T10:00:20Z,OK,METRIC_NODE_A_004"
    )
    assert content == expected_content, f"Content of {path} is incorrect. Expected lines without the corrupt metric."


def test_metrics_diff():
    path = "/home/user/metrics.diff"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "--- /home/user/raw_metrics.log" in content or "--- " in content, f"{path} does not look like a unified diff."
    assert "+++ /home/user/cleaned_metrics.log" in content or "+++ " in content, f"{path} does not look like a unified diff."
    assert "-2023-10-12T10:00:15Z,ERR,SRE_CORRUPT_0x8F9A" in content, f"{path} does not show the removal of the corrupt metric line."


def test_cleaner_rs_exists():
    path = "/home/user/cleaner.rs"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "fn main" in content, f"{path} does not appear to be a valid Rust script (missing fn main)."


def test_compiled_cleaner_filters_derived_fixture():
    raw_path = pathlib.Path("/home/user/raw_metrics.log")
    cleaned_path = pathlib.Path("/home/user/cleaned_metrics.log")
    original_raw = raw_path.read_bytes()
    original_cleaned = cleaned_path.read_bytes() if cleaned_path.exists() else None

    token = secrets.token_hex(16)
    valid_lines = [
        f"{token}-first,OK,METRIC_{token}_A",
        f"{token}-second,WARN,METRIC_{token}_B",
        f"{token}-third,OK,METRIC_{token}_C",
    ]
    bad_lines = [
        f"{token}-bad-one,ERR,prefix-{BAD_METRIC}-suffix",
        f"{token}-bad-two,ERR,{BAD_METRIC}",
    ]
    fixture = "\n".join([valid_lines[0], bad_lines[0], valid_lines[1], bad_lines[1], valid_lines[2]]) + "\n"
    expected = ("\n".join(valid_lines) + "\n").encode()

    try:
        raw_path.write_text(fixture)
        if cleaned_path.exists():
            cleaned_path.unlink()
        subprocess.run([BINARY], cwd="/home/user", check=True, timeout=10)
        assert cleaned_path.is_file(), "The compiled cleaner did not create cleaned_metrics.log."
        assert cleaned_path.read_bytes() == expected, "The compiled cleaner did not preserve valid lines and remove every line containing the corrupt metric_id."
    finally:
        raw_path.write_bytes(original_raw)
        if original_cleaned is None:
            if cleaned_path.exists():
                cleaned_path.unlink()
        else:
            cleaned_path.write_bytes(original_cleaned)
TEST_EOF

status=0
if ! timeout 30s rustc /home/user/cleaner.rs -o /tmp/cleaner_verifier_bin; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    rm -f /home/user/cleaned_metrics.log
    if ! (cd /home/user && timeout 10s /tmp/cleaner_verifier_bin); then
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
