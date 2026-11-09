#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

RAW_FILE = "/home/user/raw_telemetry.txt"
OUT_FILE = "/home/user/etl_output.csv"
C_SOURCE = "/home/user/processor.c"
C_BINARY = "/home/user/processor"

EXPECTED_RAW = (
    "1680000015;SENS_88;24.0;All gõod\n"
    "1680000020;SENS_99;100.0;Ignore this completely\n"
    "1680000010;SENS_88;22.5;Normal\n"
    "1680000005;SENS_88;21.0;Wärming üp\n"
    "1680000030;SENS_88;20.5;Ståble\n"
    "1680000025;SENS_88;25.5;Hõt!\n"
    "1680000035;SENS_88;19.0;Coolìng\n"
)


def test_etl_output_correctness():
    raw_file = RAW_FILE
    out_file = OUT_FILE

    assert os.path.exists(out_file), f"Output file {out_file} is missing. Did you run the pipeline?"
    assert os.path.exists(raw_file), f"Raw file {raw_file} is missing. It should not have been deleted."

    with open(raw_file, 'r', encoding='utf-8') as f:
        raw_content = f.read()
    assert raw_content == EXPECTED_RAW, "The supplied raw telemetry file was modified."

    # Read the raw file to compute the expected truth
    lines = raw_content.strip().split('\n')

    records = []
    for line in lines:
        if not line.strip():
            continue
        parts = line.split(';')
        if len(parts) >= 4 and parts[1] == 'SENS_88':
            records.append({
                'ts': int(parts[0]),
                'temp': float(parts[2]),
                'notes': parts[3]
            })

    # Sort chronologically
    records.sort(key=lambda x: x['ts'])

    expected_lines = []
    temps = []
    for r in records:
        temps.append(r['temp'])
        if len(temps) > 3:
            temps.pop(0)
        avg = sum(temps) / len(temps)

        # Keep only printable ASCII characters (32 to 126 inclusive)
        cleaned_notes = ''.join(c for c in r['notes'] if 32 <= ord(c) <= 126)

        expected_lines.append(f"{r['ts']},{avg:.2f},{cleaned_notes}")

    # Read actual output
    with open(out_file, 'r', encoding='utf-8') as f:
        actual_content = f.read().strip()

    actual_lines = actual_content.split('\n') if actual_content else []

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {out_file}, but got {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i+1} of {out_file}.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )


def test_c_program_exists():
    c_source = C_SOURCE
    c_binary = C_BINARY

    assert os.path.exists(c_source), f"C source file {c_source} is missing."
    assert os.path.exists(c_binary), f"Compiled C binary {c_binary} is missing."
    assert os.access(c_binary, os.X_OK), f"File {c_binary} is not executable."
    assert os.path.isfile(c_source), f"C source file {c_source} is not a regular file."
    assert os.path.isfile(c_binary), f"Compiled C binary {c_binary} is not a regular file."
    with open(c_binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {c_binary} is not a compiled ELF binary."


def _exercise_processor(executable, input_bytes, expected_lines):
    try:
        os.unlink(OUT_FILE)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [executable],
        input=input_bytes,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with status {completed.returncode}.\n"
        f"stderr: {completed.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(OUT_FILE), f"{executable} did not create {OUT_FILE}."
    with open(OUT_FILE, 'r', encoding='utf-8') as f:
        actual = f.read().splitlines()
    assert actual == expected_lines, (
        f"{executable} produced incorrect output for verifier-supplied sorted input.\n"
        f"Expected: {expected_lines!r}\nActual: {actual!r}"
    )


def test_submitted_c_processor_on_verifier_input(tmp_path):
    nonce = secrets.token_hex(5)
    base = 1700000000 + secrets.randbelow(1000000)
    rows = [
        (base, 10.0, f"first Ω {nonce}"),
        (base + 7, 20.0, "second café"),
        (base + 19, 35.0, "third ~ ok"),
        (base + 41, -5.0, "fourth naïve"),
    ]
    input_text = ''.join(
        f"{ts};SENS_88;{temp:.1f};{notes}\n" for ts, temp, notes in rows
    )

    temps = []
    expected = []
    for ts, temp, notes in rows:
        temps.append(temp)
        window = temps[-3:]
        average = sum(window) / len(window)
        cleaned = ''.join(c for c in notes if 32 <= ord(c) <= 126)
        expected.append(f"{ts},{average:.2f},{cleaned}")

    # Exercise the installed artifact.
    _exercise_processor(C_BINARY, input_text.encode('utf-8'), expected)

    # Independently compile and exercise processor.c so the submitted source must
    # itself implement the required processor rather than merely coexist with it.
    rebuilt = tmp_path / "processor_rebuilt"
    compile_result = subprocess.run(
        ["gcc", C_SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "processor.c could not be compiled.\n"
        + compile_result.stderr.decode('utf-8', errors='replace')
    )
    _exercise_processor(str(rebuilt), input_text.encode('utf-8'), expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
