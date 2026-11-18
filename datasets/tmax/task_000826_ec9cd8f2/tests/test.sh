#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest


def djb2_64(s):
    hash_val = 5381
    for char in s:
        hash_val = ((hash_val << 5) + hash_val + ord(char)) & 0xFFFFFFFFFFFFFFFF
    return hash_val


def djb2_32(s):
    hash_val = 5381
    for char in s:
        hash_val = ((hash_val << 5) + hash_val + ord(char)) & 0xFFFFFFFF
    return hash_val


def djb2_native(s):
    bits = ctypes.sizeof(ctypes.c_ulong) * 8
    mask = (1 << bits) - 1
    hash_val = 5381
    for char in s:
        hash_val = ((hash_val << 5) + hash_val + ord(char)) & mask
    return hash_val


def aligned(timestamp):
    return timestamp[:17] + "00Z"


def test_c_program_exists():
    assert os.path.isfile("/home/user/align_hash.c"), "C source file /home/user/align_hash.c is missing."


def test_executable_exists():
    assert os.path.isfile("/home/user/align_hash"), "Executable /home/user/align_hash is missing."
    assert os.access("/home/user/align_hash", os.X_OK), "/home/user/align_hash is not executable."


def test_bash_script_exists():
    assert os.path.isfile("/home/user/run_pipeline.sh"), "Bash script /home/user/run_pipeline.sh is missing."


def test_final_output_exists_and_correct():
    output_file = "/home/user/final_output.csv"
    assert os.path.isfile(output_file), f"Final output file {output_file} is missing."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {output_file}, found {len(lines)}."

    expected_64 = [
        f"2023-10-25T14:32:00Z,S1,{djb2_64('battery_low')}",
        f"2023-10-25T14:35:00Z,S2,{djb2_64('temp_high')}",
        f"2023-10-25T14:40:00Z,S1,{djb2_64('rebooting')}"
    ]

    expected_32 = [
        f"2023-10-25T14:32:00Z,S1,{djb2_32('battery_low')}",
        f"2023-10-25T14:35:00Z,S2,{djb2_32('temp_high')}",
        f"2023-10-25T14:40:00Z,S1,{djb2_32('rebooting')}"
    ]

    expected_64.sort()
    expected_32.sort()

    is_64_match = lines == expected_64
    is_32_match = lines == expected_32

    if not (is_64_match or is_32_match):
        for idx, line in enumerate(lines):
            parts = line.split(',')
            assert len(parts) == 3, f"Line {idx+1} does not have exactly 3 comma-separated fields: {line}"

            ts, sid, hash_val = parts
            assert ts.endswith("00Z"), f"Timestamp not correctly aligned to minute in line {idx+1}: {ts}"
            assert hash_val.isdigit(), f"Hash value is not numeric in line {idx+1}: {hash_val}"

        pytest.fail(f"File contents do not match expected sorted output. Found: {lines}")


def _exercise_filter(executable, records):
    input_text = "".join(f"{ts},{sid},{payload}\n" for ts, sid, payload in records)
    result = subprocess.run(
        [executable],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Filter failed: {result.stderr}"
    expected = [
        f"{aligned(ts)},{sid},{djb2_native(payload)}"
        for ts, sid, payload in records
    ]
    assert result.stdout.splitlines() == expected


def test_c_source_and_compiled_filter_behavior():
    with open("/home/user/align_hash", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/align_hash is not a compiled ELF executable."

    token = secrets.token_hex(8)
    long_payload = "long_" + token + ("x" * 210)
    records = [
        ("2026-01-03T09:07:41Z", "RX9", "alpha_" + token),
        ("2024-12-31T23:59:01Z", "Q2", "privacy_" + token),
        ("2025-06-11T00:00:59Z", "LONG", long_payload),
    ]

    _exercise_filter("/home/user/align_hash", records)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "align_hash_rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/align_hash.c", "-o", rebuilt],
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, f"align_hash.c does not compile: {compile_result.stderr}"
        _exercise_filter(rebuilt, records)


def test_pipeline_executes_on_dynamic_csv_inputs():
    data_dir = "/home/user/data"
    output_file = "/home/user/final_output.csv"
    token = secrets.token_hex(10)

    records_a = [
        ("2026-02-14T10:11:57Z", "A7", "event_" + token),
        ("2026-02-14T10:12:03Z", "B8", "status_" + token),
    ]
    records_b = [
        ("2026-02-14T10:11:02Z", "A7", "event_" + token),
        ("2026-02-14T10:13:44Z", "C9", "reading_" + token),
    ]
    records_c = [
        ("2025-08-01T00:00:09Z", "Z1", "other_" + token),
        ("2026-02-14T10:12:49Z", "B8", "status_" + token),
    ]
    all_records = records_a + records_b + records_c
    expected = sorted(set(
        f"{aligned(ts)},{sid},{djb2_native(payload)}"
        for ts, sid, payload in all_records
    ))

    with tempfile.TemporaryDirectory() as backup_root:
        backup_data = os.path.join(backup_root, "data")
        shutil.copytree(data_dir, backup_data)
        had_output = os.path.exists(output_file)
        backup_output = os.path.join(backup_root, "final_output.csv")
        if had_output:
            shutil.copy2(output_file, backup_output)

        observed = None
        try:
            shutil.rmtree(data_dir)
            os.makedirs(data_dir)
            for name, records in [
                ("dynamic_a.csv", records_a),
                ("dynamic_b.csv", records_b),
                ("dynamic_c.csv", records_c),
            ]:
                with open(os.path.join(data_dir, name), "w") as f:
                    for ts, sid, payload in records:
                        f.write(f"{ts},{sid},{payload}\n")
            with open(os.path.join(data_dir, "ignored.txt"), "w") as f:
                f.write("this file must not be ingested\n")

            result = subprocess.run(
                ["bash", "/home/user/run_pipeline.sh"],
                cwd="/home/user",
                text=True,
                capture_output=True,
                timeout=15,
            )
            assert result.returncode == 0, f"Pipeline failed: {result.stderr}"
            assert os.path.isfile(output_file), "Pipeline did not create /home/user/final_output.csv."
            with open(output_file) as f:
                observed = [line.rstrip("\n") for line in f if line.rstrip("\n")]
        finally:
            shutil.rmtree(data_dir, ignore_errors=True)
            shutil.copytree(backup_data, data_dir)
            if had_output:
                shutil.copy2(backup_output, output_file)
            elif os.path.exists(output_file):
                os.remove(output_file)

    assert observed == expected, f"Pipeline output was not correctly transformed, deduplicated, and sorted: {observed}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
