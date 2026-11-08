#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
from pathlib import Path

CSV_PATH = Path("/home/user/anomalies.csv")
TELEMETRY_PATH = Path("/home/user/telemetry.bin")
HEADER = "string_id,language,current_width,rolling_avg"

CANONICAL_RECORDS = [
    (1, 50, 55, 60, 55, 40),
    (2, 52, 60, 62, 58, 42),
    (3, 48, 52, 58, 50, 45),
    (4, 55, 60, 65, 60, 48),
    (5, 60, 150, 70, 65, 110),
    (6, 40, 45, 50, 48, 40),
    (7, 45, 50, 55, 50, 42),
    (8, 48, 55, 58, 52, 45),
    (9, 50, 58, 60, 55, 48),
    (10, 55, 60, 105, 60, 50),
]

EXPECTED_CANONICAL = [
    "string_id,language,current_width,rolling_avg",
    "5,FR,150,56",
    "5,JA,110,43",
    "10,DE,105,55",
]


def test_anomalies_csv_exists():
    """Test that the anomalies.csv file has been created."""
    file_path = "/home/user/anomalies.csv"
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_anomalies_csv_content():
    """Test that the anomalies.csv file contains the correct results."""
    file_path = "/home/user/anomalies.csv"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "string_id,language,current_width,rolling_avg",
        "5,FR,150,56",
        "5,JA,110,43",
        "10,DE,105,55"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual.strip()}'."


def expected_lines(records):
    lines = [HEADER]
    windows = [[], [], [], []]
    languages = ["FR", "DE", "ES", "JA"]
    for record in records:
        string_id = record[0]
        for index, language in enumerate(languages):
            width = record[index + 2]
            window = windows[index]
            average = sum(window) // len(window) if window else 0
            if width > 100 and width > (average * 3) // 2:
                lines.append(f"{string_id},{language},{width},{average}")
            window.append(width)
            if len(window) > 4:
                del window[0]
    return lines


def write_records(records):
    with TELEMETRY_PATH.open("wb") as f:
        for record in records:
            f.write(struct.pack("<iiiiii", *record))


def run_and_check(program, records):
    write_records(records)
    try:
        CSV_PATH.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [str(program)], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, check=False
    )
    assert result.returncode == 0, (
        f"Compiled C program exited with {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert CSV_PATH.exists() and CSV_PATH.is_file(), "Program did not create /home/user/anomalies.csv"
    actual = [line.strip() for line in CSV_PATH.read_text(encoding="utf-8").strip().splitlines()]
    expected = expected_lines(records)
    assert actual == expected, f"Program output mismatch. Expected {expected!r}, got {actual!r}"


def test_c_program_is_compiled_and_processes_telemetry():
    home = Path("/home/user")
    sources = sorted(p for p in home.rglob("*.c") if p.is_file())
    assert sources, "No C source program was found under /home/user"

    compiled_artifacts = []
    for path in home.rglob("*"):
        if not path.is_file() or not os.access(path, os.X_OK):
            continue
        try:
            if path.read_bytes()[:4] == b"\x7fELF":
                compiled_artifacts.append(path)
        except OSError:
            pass
    assert compiled_artifacts, "No compiled ELF executable was found under /home/user"

    verifier_binary = Path("/tmp/submission_process_telemetry")
    compile_result = subprocess.run(
        ["gcc", *map(str, sources), "-o", str(verifier_binary), "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=False
    )
    assert compile_result.returncode == 0, (
        "The submitted C source could not be compiled: "
        + compile_result.stderr.decode(errors="replace")
    )

    rng = random.Random(int.from_bytes(os.urandom(16), "little"))
    random_records = []
    string_id = 100
    for _ in range(17):
        string_id += rng.randint(1, 4)
        random_records.append((
            string_id,
            rng.randint(20, 180),
            rng.randint(20, 180),
            rng.randint(20, 180),
            rng.randint(20, 180),
            rng.randint(20, 180),
        ))

    boundary_records = [
        (21, 50, 60, 80, 100, 40),
        (22, 50, 60, 80, 100, 40),
        (23, 50, 60, 80, 100, 40),
        (24, 50, 60, 80, 100, 40),
        (25, 50, 101, 120, 151, 101),
        (26, 50, 91, 121, 151, 61),
        (27, 50, 180, 101, 180, 180),
    ]

    try:
        run_and_check(verifier_binary, CANONICAL_RECORDS)
        run_and_check(verifier_binary, boundary_records)
        run_and_check(verifier_binary, random_records)
    finally:
        write_records(CANONICAL_RECORDS)

    run_and_check(verifier_binary, CANONICAL_RECORDS)
    actual = [line.strip() for line in CSV_PATH.read_text(encoding="utf-8").strip().splitlines()]
    assert actual == EXPECTED_CANONICAL
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
