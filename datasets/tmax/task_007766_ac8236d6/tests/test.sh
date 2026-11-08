#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

INPUT_FILE = "/home/user/sensor_stream.jsonl"
OUTPUT_FILE = "/home/user/pipeline_output.txt"
SCRIPT_FILE = "/home/user/process_stream.py"


def expected_output(lines):
    expected_lines = []
    window = []
    for i, line in enumerate(lines, start=1):
        try:
            data = json.loads(line)
            window.append(data["temperature"])
            if len(window) > 3:
                window.pop(0)
            avg = sum(window) / len(window)
            expected_lines.append(
                f"SUCCESS: Sensor {data['sensor_id']} processed. Rolling avg: {avg:.2f}"
            )
        except Exception:
            expected_lines.append(f"ERROR: Line {i} failed validation")
    return "\n".join(expected_lines)


def run_fixture(lines):
    # Recreate the input from verifier-controlled data so agent modifications to the
    # original input cannot make the expected and actual outputs vacuously empty.
    os.unlink(INPUT_FILE)
    with open(INPUT_FILE, "x", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)

    result = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_stream.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found: {OUTPUT_FILE}"
    assert stat.S_ISREG(os.lstat(OUTPUT_FILE).st_mode), "Output must be a regular file"

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        actual = f.read().strip()
    expected = expected_output(lines)
    assert actual == expected, (
        f"Pipeline output does not match expected.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def test_pipeline_script_and_output():
    # Preserve the original existence assertions and additionally require the
    # requested Python artifact to be a real file.
    assert os.path.isfile(INPUT_FILE), f"Input file not found: {INPUT_FILE}"
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found: {OUTPUT_FILE}"
    assert os.path.isfile(SCRIPT_FILE), f"Processing script not found: {SCRIPT_FILE}"
    assert stat.S_ISREG(os.lstat(INPUT_FILE).st_mode), "Input must be a regular file"
    assert stat.S_ISREG(os.lstat(OUTPUT_FILE).st_mode), "Output must be a regular file"
    assert stat.S_ISREG(os.lstat(SCRIPT_FILE).st_mode), "Script must be a regular file"

    original_fixture = [
        '{"sensor_id": "S01", "temperature": 20.0, "meta": "init"}',
        '{"sensor_id": "S02", "temperature": 22.0, "meta": "bad \\uZZZZ unicode"}',
        '{"sensor_id": "S03", "temperature": 25.0, "meta": "ok"}',
        '{"sensor_id": "S04", "temperature": 27.0, "meta": "normal"}',
        '{"sensor_id": "S05", "temperature": 30.0, "meta": "invalid \\u123"}',
        '{"sensor_id": "S06", "temperature": 23.0, "meta": "good"}',
        '{"sensor_id": "S07", "temperature": 28.0, "meta": "final"}',
    ]
    run_fixture(original_fixture)

    # Exercise the submitted script on unpredictable values and multiple invalid
    # records, deriving the expected result independently in the verifier.
    token = secrets.token_hex(6)
    temperatures = [
        (secrets.randbelow(5000) - 1000) / 10.0,
        (secrets.randbelow(5000) - 1000) / 10.0,
        (secrets.randbelow(5000) - 1000) / 10.0,
        (secrets.randbelow(5000) - 1000) / 10.0,
        (secrets.randbelow(5000) - 1000) / 10.0,
    ]
    generated_fixture = [
        json.dumps({"sensor_id": f"A-{token}", "temperature": temperatures[0], "meta": "ok"}),
        f'{{"sensor_id":"BAD-{token}","temperature":99,"meta":"bad \\uZZZZ"}}',
        json.dumps({"sensor_id": f"B-{token}", "temperature": temperatures[1], "meta": "snowman ☃"}),
        '{not valid json}',
        json.dumps({"sensor_id": f"C-{token}", "temperature": temperatures[2], "meta": "ok"}),
        json.dumps({"sensor_id": f"D-{token}", "temperature": temperatures[3], "meta": "ok"}),
        json.dumps({"sensor_id": f"E-{token}", "temperature": temperatures[4], "meta": "ok"}),
    ]
    run_fixture(generated_fixture)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
