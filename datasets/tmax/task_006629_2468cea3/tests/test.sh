#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

PROCESS_PATH = "/home/user/process.py"
DATA_PATH = "/home/user/data.jsonl"
OUTPUT_PATH = "/home/user/output.txt"


def run_process_and_check(expected):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["python3", PROCESS_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} does not exist after running process.py."
    )

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert content == str(expected), (
        f"Expected output.txt to contain '{expected}', but found '{content}'."
    )
    return content


def test_final_state_and_behavior():
    assert os.path.isfile(PROCESS_PATH), f"Script {PROCESS_PATH} does not exist."

    with open(PROCESS_PATH, "r") as f:
        content = f.read()

    # Requirement: Do not modify the two pandas-related lines.
    assert "df.append(" in content, (
        "You modified or removed the df.append line, which was forbidden."
    )
    assert "pd.DataFrame()" in content, (
        "You modified or removed the pd.DataFrame() line, which was forbidden."
    )

    # Preserve the original synchronization and JSON checks.
    has_lock = any(
        lock_term in content
        for lock_term in ["Lock()", "RLock()", "Semaphore", "Mutex"]
    )
    assert has_lock, (
        "Could not find a thread synchronization mechanism "
        "(like threading.Lock()) in process.py."
    )
    assert "json.loads" in content, "Expected json.loads to still be used in process.py"

    result = subprocess.run(
        ["pip", "show", "pandas"], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, "Failed to run pip show pandas."
    version_line = next(
        (line for line in result.stdout.split("\n") if line.startswith("Version:")),
        None,
    )
    assert version_line is not None, "Could not find Version in pip show pandas output."
    version = version_line.split(" ")[1]
    major_version = int(version.split(".")[0])
    assert major_version < 2, (
        f"Expected pandas version < 2.0.0, but found {version}."
    )

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    verified_original_output = None
    try:
        # Execute the submitted artifact against the supplied incident data.
        assert len(original_data.splitlines()) == 1000, (
            "The supplied data.jsonl must still contain its original 1000 records."
        )
        run_process_and_check(1000)
        with open(OUTPUT_PATH, "rb") as f:
            verified_original_output = f.read()

        # Exercise parsing and synchronized counting on verifier-generated data.
        # The expected answer is derived here rather than read from a fixed output.
        lines = []
        expected = 0
        for i in range(503):
            record = {"id": 10000 + i}
            if i % 5 != 0:
                record["value"] = i * 3
                expected += 1
            encoded = json.dumps(record, separators=(",", ":"))
            if i % 7 == 0:
                encoded = encoded[:-1] + ",}"
            lines.append(encoded + "\n")

        with open(DATA_PATH, "w") as f:
            f.writelines(lines)

        run_process_and_check(expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)

        if verified_original_output is not None:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(verified_original_output)
        elif original_output is not None:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
