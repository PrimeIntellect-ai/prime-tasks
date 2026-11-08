#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import pytest

INPUT_FILE = "/home/user/telemetry.csv"
OUTPUT_FILE = "/home/user/processed_locales.jsonl"
SOURCE_FILE = "/home/user/process_loc.cpp"
BINARY_FILE = "/tmp/process_loc_verified"
EXPECTED_KEYS = {"aligned_time", "locale", "rolling_avg_latency", "message_utf8"}


def compute_expected_data(input_path):
    expected = []
    locale_latencies = {}

    with open(input_path, "rb") as f:
        lines = f.read().strip().split(b'\n')

    for line in lines:
        if not line:
            continue
        parts = line.split(b',', 4)
        if len(parts) != 5:
            continue

        timestamp_raw = parts[0].decode('ascii')
        locale = parts[1].decode('ascii')
        encoding = parts[2].decode('ascii')
        latency = float(parts[3].decode('ascii'))
        message_raw = parts[4]

        aligned_time = timestamp_raw[:17] + "00Z"

        if encoding == "ISO-8859-1":
            message_utf8 = message_raw.decode('iso-8859-1')
        else:
            message_utf8 = message_raw.decode('utf-8')

        if locale not in locale_latencies:
            locale_latencies[locale] = []
        locale_latencies[locale].append(latency)
        recent_latencies = locale_latencies[locale][-3:]
        rolling_avg = sum(recent_latencies) / len(recent_latencies)

        expected.append({
            "aligned_time": aligned_time,
            "locale": locale,
            "rolling_avg_latency": round(rolling_avg, 2),
            "message_utf8": message_utf8
        })

    return expected


def assert_output_matches(input_path, output_path):
    expected_data = compute_expected_data(input_path)

    with open(output_path, "r", encoding="utf-8") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == len(expected_data), (
        f"Expected {len(expected_data)} JSON lines, but found {len(lines)}."
    )

    for i, (line, expected_obj) in enumerate(zip(lines, expected_data)):
        try:
            actual_obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        assert "aligned_time" in actual_obj, f"Line {i+1} missing 'aligned_time' key."
        assert "locale" in actual_obj, f"Line {i+1} missing 'locale' key."
        assert "rolling_avg_latency" in actual_obj, f"Line {i+1} missing 'rolling_avg_latency' key."
        assert "message_utf8" in actual_obj, f"Line {i+1} missing 'message_utf8' key."
        assert set(actual_obj.keys()) == EXPECTED_KEYS, f"Line {i+1} does not have the exact required keys."

        assert actual_obj["aligned_time"] == expected_obj["aligned_time"], f"Line {i+1} aligned_time mismatch."
        assert actual_obj["locale"] == expected_obj["locale"], f"Line {i+1} locale mismatch."
        assert actual_obj["message_utf8"] == expected_obj["message_utf8"], f"Line {i+1} message_utf8 mismatch."

        actual_avg = float(actual_obj["rolling_avg_latency"])
        expected_avg = expected_obj["rolling_avg_latency"]
        assert abs(actual_avg - expected_avg) < 0.015, (
            f"Line {i+1} rolling_avg_latency mismatch: expected ~{expected_avg}, got {actual_avg}"
        )

        numeric_tokens = re.findall(
            r'"rolling_avg_latency"\s*:\s*(-?(?:0|[1-9]\d*)\.\d{2})(?=\s*[,}])',
            line
        )
        assert len(numeric_tokens) == 1, (
            f"Line {i+1} rolling_avg_latency must be a JSON number written with exactly two decimal places."
        )


def test_source_file_exists():
    assert os.path.exists(SOURCE_FILE), f"Source file {SOURCE_FILE} does not exist."
    assert os.path.isfile(SOURCE_FILE), f"Expected {SOURCE_FILE} to be a regular file."


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"Expected {OUTPUT_FILE} to be a file."


def test_output_file_contents():
    assert os.path.exists(INPUT_FILE), f"Input file {INPUT_FILE} is missing, cannot compute expected state."
    assert_output_matches(INPUT_FILE, OUTPUT_FILE)


def test_compiled_program_transforms_new_input():
    original_input = open(INPUT_FILE, "rb").read()
    output_existed = os.path.exists(OUTPUT_FILE)
    original_output = open(OUTPUT_FILE, "rb").read() if output_existed else None

    challenge = (
        b"2025-02-03T11:22:59Z,de-DE,UTF-8,10,Start\n"
        b"2025-02-03T11:23:01Z,pt-BR,ISO-8859-1,101,Ol\xe1\n"
        b"2025-02-03T11:24:44Z,de-DE,ISO-8859-1,20,Gr\xfc\xdfe\n"
        b"2025-02-03T11:25:17Z,pt-BR,UTF-8,102,Ação\n"
        b"2025-02-03T11:26:33Z,de-DE,UTF-8,31,Weiter\n"
        b"2025-02-03T11:27:48Z,de-DE,ISO-8859-1,50,Sp\xe4ter\n"
        b"2025-02-03T11:28:09Z,it-IT,UTF-8,77,Perché\n"
    )

    try:
        with open(INPUT_FILE, "wb") as f:
            f.write(challenge)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        subprocess.run([BINARY_FILE], cwd="/home/user", check=True, timeout=10)
        assert os.path.isfile(OUTPUT_FILE), "Compiled program did not create the required output file."
        assert_output_matches(INPUT_FILE, OUTPUT_FILE)
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        if output_existed:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
TEST_EOF

if test -f /home/user/process_loc.cpp \
   && g++ -std=c++17 /home/user/process_loc.cpp -o /tmp/process_loc_verified \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
