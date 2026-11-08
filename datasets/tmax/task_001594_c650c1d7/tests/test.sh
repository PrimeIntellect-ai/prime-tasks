#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import secrets
import string
import subprocess


def test_etl_go_exists():
    etl_path = "/home/user/etl.go"
    assert os.path.exists(etl_path), f"The Go program file {etl_path} does not exist."
    assert os.path.isfile(etl_path), f"{etl_path} is not a file."


def test_output_csv_exists_and_content():
    output_path = "/home/user/output.csv"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist. Did you run your Go program?"
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    expected_csv = """ts,id,temp_c,rolling_avg_temp_c
100,S1,27.00,27.00
102,S1,30.00,28.50
104,S2,17.00,24.67
106,S1,10.00,19.00
108,S4,40.00,22.33"""

    with open(output_path, "r") as f:
        actual_content = f.read().strip()

    # Normalize line endings to avoid issues with \r\n vs \n
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_csv.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {output_path} does not match the expected output.\n"
        f"Expected:\n{expected_csv}\n\nActual:\n{actual_content}"
    )


def _expected_output(records):
    lines = ["ts,id,temp_c,rolling_avg_temp_c"]
    window = []
    for record in records:
        tk = record.get("tk")
        h = record.get("h")
        sensor_id = record.get("id")
        if tk is None or tk <= 0 or h < 0.0 or h > 100.0 or sensor_id == "":
            continue
        temp_c = tk - 273.15
        window.append(temp_c)
        window = window[-3:]
        rolling = sum(window) / len(window)
        lines.append(f"{record['ts']},{sensor_id},{temp_c:.2f},{rolling:.2f}")
    return lines


def test_etl_executes_and_processes_unseen_input():
    rng = secrets.SystemRandom()
    base_ts = rng.randrange(10000, 90000)
    alphabet = string.ascii_letters + string.digits
    ids = ["T" + "".join(rng.choice(alphabet) for _ in range(10)) for _ in range(7)]
    temps_c = [rng.randrange(-30, 71) for _ in range(7)]

    def valid(index, offset, humidity=50.0):
        return {
            "ts": base_ts + offset,
            "id": ids[index],
            "tk": temps_c[index] + 273.15,
            "h": humidity,
        }

    records = [
        valid(0, 0),
        {"ts": base_ts + 1, "id": "bad_h_high", "tk": 999.15, "h": 100.01},
        valid(1, 2),
        {"ts": base_ts + 3, "id": "zero_tk", "tk": 0, "h": 40.0},
        valid(2, 4),
        {"ts": base_ts + 5, "id": "", "tk": 350.15, "h": 40.0},
        valid(3, 6, 0.0),
        {"ts": base_ts + 7, "id": "missing_tk", "h": 40.0},
        valid(4, 8, 100.0),
        {"ts": base_ts + 9, "id": "negative_tk", "tk": -2.0, "h": 40.0},
        valid(5, 10),
        {"ts": base_ts + 11, "id": "bad_h_low", "tk": 310.15, "h": -0.01},
        valid(6, 12),
    ]
    input_text = "\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n"

    result = subprocess.run(
        ["go", "run", "/home/user/etl.go"],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"go run failed with exit code {result.returncode}:\n{result.stderr}"

    actual_lines = result.stdout.replace("\r\n", "\n").strip().splitlines()
    expected_lines = _expected_output(records)
    assert actual_lines == expected_lines, (
        "The Go program produced incorrect output for an unseen input stream.\n"
        f"Expected:\n{os.linesep.join(expected_lines)}\n\n"
        f"Actual stdout:\n{result.stdout}\n\nStderr:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
