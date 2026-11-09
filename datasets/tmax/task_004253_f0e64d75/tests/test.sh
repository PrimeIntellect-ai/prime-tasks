#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import stat
import string
import subprocess
from collections import defaultdict

RAW_FILE = "/home/user/raw_telemetry.csv"
PROCESSED_FILE = "/home/user/processed_telemetry.csv"
SCRIPT_FILE = "/home/user/process_telemetry.sh"


def compute_expected_telemetry(raw_path):
    data = defaultdict(lambda: defaultdict(lambda: {'latencies': [], 'chars': 0}))

    with open(raw_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            epoch_sec = int(row[0])
            region = row[1]
            latency = float(row[2])
            error_msg = row[3] if len(row) > 3 else ""

            minute_epoch = (epoch_sec // 60) * 60
            data[region][minute_epoch]['latencies'].append(latency)
            data[region][minute_epoch]['chars'] += len(error_msg)

    expected_rows = []

    for region in sorted(data.keys()):
        region_data = data[region]
        min_epoch = min(region_data.keys())
        max_epoch = max(region_data.keys())
        current_epoch = min_epoch
        last_latency = None
        history = []

        while current_epoch <= max_epoch:
            if current_epoch in region_data:
                latencies = region_data[current_epoch]['latencies']
                mean_latency = sum(latencies) / len(latencies)
                chars = region_data[current_epoch]['chars']
                last_latency = mean_latency
            else:
                mean_latency = last_latency
                chars = 0

            history.append(mean_latency)
            if len(history) > 5:
                history.pop(0)

            rolling_avg = sum(history) / len(history)
            expected_rows.append(
                f"{current_epoch},{region},{mean_latency:.2f},{rolling_avg:.2f},{chars}"
            )
            current_epoch += 60

    return expected_rows


def run_script():
    result = subprocess.run(
        [SCRIPT_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_output():
    with open(PROCESSED_FILE, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    st = os.stat(SCRIPT_FILE)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_FILE} is not executable."


def test_script_runs_on_original_input():
    if os.path.exists(PROCESSED_FILE):
        os.remove(PROCESSED_FILE)
    run_script()
    assert os.path.isfile(PROCESSED_FILE), (
        f"Script did not create {PROCESSED_FILE}."
    )


def test_processed_file_exists():
    assert os.path.exists(PROCESSED_FILE), f"Output file {PROCESSED_FILE} does not exist. Did the script run?"
    assert os.path.isfile(PROCESSED_FILE), f"Path {PROCESSED_FILE} is not a file."


def test_processed_telemetry_content():
    assert os.path.exists(RAW_FILE), f"Raw file {RAW_FILE} is missing, cannot verify."

    expected_lines = compute_expected_telemetry(RAW_FILE)
    actual_lines = read_output()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)} in {PROCESSED_FILE}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Mismatch at row {i+1}.\nExpected: {expected}\nActual:   {actual}"


def test_script_transforms_unseen_input():
    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(8))
    base = (rng.randrange(1700000000, 1900000000) // 60) * 60
    shift = rng.randrange(0, 40)

    region_a = "A_" + token
    region_b = "M_" + token[::-1]
    region_c = "Z_" + token

    rows = [
        [base + 3, region_a, 101 + shift, "ok" + token],
        [base + 49, region_a, 119 + shift, "障害🙂"],
        [base + 127, region_a, 201 + shift, "Fehler"],
        [base + 304, region_a, 151 + shift, "タイムアウト"],
        [base + 347, region_a, 169 + shift, ""],
        [base + 65, region_b, 301 + shift, "エラー"],
        [base + 246, region_b, 321 + shift, "überlastet"],
        [base + 22, region_c, 80 + shift, "é🙂"],
    ]
    rng.shuffle(rows)

    original_raw = open(RAW_FILE, 'rb').read()
    original_output = open(PROCESSED_FILE, 'rb').read() if os.path.exists(PROCESSED_FILE) else None

    try:
        with open(RAW_FILE, 'w', encoding='utf-8', newline='') as f:
            csv.writer(f, lineterminator='\n').writerows(rows)

        expected_lines = compute_expected_telemetry(RAW_FILE)
        if os.path.exists(PROCESSED_FILE):
            os.remove(PROCESSED_FILE)

        run_script()
        assert os.path.isfile(PROCESSED_FILE), "Script did not create output for unseen input."
        actual_lines = read_output()
        assert actual_lines == expected_lines, (
            "Script output was incorrect for an unseen input.\n"
            f"Expected:\n" + "\n".join(expected_lines) +
            "\nActual:\n" + "\n".join(actual_lines)
        )
    finally:
        with open(RAW_FILE, 'wb') as f:
            f.write(original_raw)
        if original_output is None:
            if os.path.exists(PROCESSED_FILE):
                os.remove(PROCESSED_FILE)
        else:
            with open(PROCESSED_FILE, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
