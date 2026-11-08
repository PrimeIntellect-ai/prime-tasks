#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/monitor.sh"
ORIGINAL_DUMP = "/home/user/traffic.dump"
OUTPUT_FILE = "/home/user/final_uptime.txt"


def expected_uptime(timestamps):
    ordered = sorted(timestamps)
    return sum(
        later - earlier
        for earlier, later in zip(ordered, ordered[1:])
        if later - earlier <= 20
    )


def timestamps_from_dump(path):
    timestamps = []
    with open(path, "r", encoding="utf-8") as dump:
        for line in dump:
            fields = line.split()
            if not fields or not fields[0].startswith("E..") or len(fields) < 3:
                continue
            payload = fields[2]
            payload += "=" * (-len(payload) % 4)
            decoded = base64.b64decode(payload).decode("utf-8")
            node, timestamp, status = decoded.split(":")
            if node == "node-1" and status == "OK":
                timestamps.append(int(timestamp))
    return timestamps


def run_monitor(dump_path):
    result = subprocess.run(
        [SCRIPT, dump_path],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"monitor.sh failed for {dump_path} with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert re.fullmatch(r"\s*\d+\s*", result.stdout), (
        f"monitor.sh must output only the numeric uptime, got {result.stdout!r}"
    )
    return int(result.stdout.strip())


def write_dump(path, records):
    with open(path, "w", encoding="utf-8") as dump:
        for index, (node, timestamp) in enumerate(records):
            payload = base64.b64encode(
                f"{node}:{timestamp}:OK".encode("utf-8")
            ).decode("ascii")
            dump.write(
                f"12:00:{index % 60:02d}.000 IP 10.0.0.2.1234 > "
                "10.0.0.1.8080: UDP, length 32\n"
            )
            dump.write(f"E.. ....  {payload}\n")


def test_final_uptime_file_exists_and_correct():
    """Check if final_uptime.txt contains the requested result."""
    assert os.path.isfile(OUTPUT_FILE), (
        f"Missing file: {OUTPUT_FILE}. Did you save the output as requested?"
    )

    with open(OUTPUT_FILE, "r", encoding="utf-8") as output:
        content = output.read().strip()

    assert content != "", f"The file {OUTPUT_FILE} is empty."

    try:
        uptime_val = int(content)
    except ValueError:
        pytest.fail(
            f"The file {OUTPUT_FILE} does not contain a valid integer. "
            f"Found: {content!r}"
        )

    expected = 20
    assert uptime_val == expected, (
        f"Calculated uptime is incorrect. Expected {expected}, but got {uptime_val}."
    )


def test_monitor_is_an_executable_bash_script():
    assert os.path.isfile(SCRIPT), f"Missing monitoring script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Monitoring script is not executable: {SCRIPT}"
    with open(SCRIPT, "rb") as script:
        first_line = script.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, (
        f"{SCRIPT} must remain an executable Bash script"
    )


def test_monitor_processes_provided_dump():
    timestamps = timestamps_from_dump(ORIGINAL_DUMP)
    assert run_monitor(ORIGINAL_DUMP) == expected_uptime(timestamps)


def test_monitor_processes_generated_out_of_order_dumps():
    secure_random = random.SystemRandom()

    for case_number in range(4):
        base = 1_700_000_000 + secure_random.randrange(1_000_000)
        gaps = [
            secure_random.randint(1, 19),
            20,
            21,
            secure_random.randint(2, 18),
            secure_random.randint(22, 40),
            secure_random.randint(1, 20),
        ]
        node_one = [base]
        for gap in gaps:
            node_one.append(node_one[-1] + gap)

        records = [("node-1", timestamp) for timestamp in node_one]
        records.extend([
            ("node-2", base + 3),
            ("node-2", base + 500),
        ])
        secure_random.shuffle(records)

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=f"-{case_number}.dump", delete=False
        ) as temporary:
            dump_path = temporary.name

        try:
            write_dump(dump_path, records)
            actual = run_monitor(dump_path)
            expected = expected_uptime(node_one)
            assert actual == expected, (
                f"Generated dump produced {actual}, expected {expected} from "
                f"chronologically ordered node-1 timestamps {sorted(node_one)}"
            )
        finally:
            os.unlink(dump_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
