#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import string
import subprocess
from pathlib import Path

SOURCE = Path("/home/user/process_logs.go")
RAW = Path("/home/user/raw_logs.txt")
CSV = Path("/home/user/clean_metrics.csv")
BINARY = Path("/tmp/process_logs_submission")

ORIGINAL_RAW = """[2023-10-01T10:00:00Z] INFO - User accessed /api/v1/data | response_ms=45 load=0.55
[2023-10-01T10:02:00Z] INFO - User accessed /api/v1/status | response_ms=10 load=0.65
[2023-10-01T10:01:00Z] INFO - User accessed /api/v1/users | response_ms=120 load=
[2023-10-01T10:02:00Z] INFO - User accessed /api/v1/status | response_ms=10 load=0.65
[2023-10-01T10:03:00Z] ERROR - Database connection failed
[2023-10-01T10:04:00Z] INFO - User accessed /api/v1/data | response_ms=50 load=0.75
[2023-10-01T10:05:00Z] INFO - User accessed /api/v1/settings | response_ms=30 load=
[2023-10-01T10:06:00Z] INFO - User accessed /api/v1/profile | response_ms=80 load=0.85
"""

ORIGINAL_EXPECTED = (
    "Timestamp,Endpoint,ResponseTimeMs,ServerLoad\n"
    "2023-10-01T10:00:00Z,/api/v1/data,45,0.55\n"
    "2023-10-01T10:01:00Z,/api/v1/users,120,0.60\n"
    "2023-10-01T10:02:00Z,/api/v1/status,10,0.65\n"
    "2023-10-01T10:04:00Z,/api/v1/data,50,0.75\n"
    "2023-10-01T10:05:00Z,/api/v1/settings,30,0.80\n"
    "2023-10-01T10:06:00Z,/api/v1/profile,80,0.85"
)


def run_program():
    result = subprocess.run(
        [str(BINARY)], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled Go program exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert CSV.exists(), f"File {CSV} is missing."
    assert CSV.is_file(), f"{CSV} is not a file."


def assert_csv_lines(expected_content):
    content = CSV.read_text().strip()
    expected_lines = expected_content.split("\n")
    actual_lines = content.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in the CSV, but found {len(actual_lines)}."
    )
    for i, (expected_line, actual_line) in enumerate(zip(expected_lines, actual_lines)):
        assert actual_line.strip() == expected_line.strip(), (
            f"Mismatch at line {i+1}.\nExpected: {expected_line}\nFound:    {actual_line}"
        )


def test_go_program_and_output():
    assert SOURCE.exists(), f"Required Go source {SOURCE} is missing."
    assert SOURCE.is_file(), f"{SOURCE} is not a regular file."

    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(SOURCE)],
        cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, (
        f"process_logs.go does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    try:
        # Preserve the original exact-content assertion, but require the submitted
        # program to produce that content itself.
        RAW.write_text(ORIGINAL_RAW)
        if CSV.exists():
            CSV.unlink()
        run_program()
        assert_csv_lines(ORIGINAL_EXPECTED)

        # Exercise the compiled artifact on fresh values so a hardcoded CSV cannot pass.
        token = ''.join(secrets.choice(string.ascii_lowercase) for _ in range(10))
        a = secrets.choice([21, 23, 25, 27, 29, 31, 33, 35])
        b = secrets.choice([61, 63, 65, 67, 69, 71, 73, 75])
        c = secrets.choice([81, 83, 85, 87, 89, 91, 93, 95])
        r0, r1, r2, r3, r4 = [secrets.randbelow(180) + 1 for _ in range(5)]
        ep0 = f"/api/{token}/alpha"
        ep1 = f"/api/{token}/beta"
        ep2 = f"/api/{token}/gamma"
        ep3 = f"/api/{token}/delta"
        ep4 = f"/api/{token}/omega"

        lines = [
            f"[2024-07-19T12:03:00Z] INFO - User accessed {ep3} | response_ms={r3} load={b/100:.2f}",
            "this line is malformed and must be ignored",
            f"[2024-07-19T12:01:00Z] INFO - User accessed {ep1} | response_ms={r1} load=",
            f"[2024-07-19T12:04:00Z] INFO - User accessed {ep4} | response_ms={r4} load={c/100:.2f}",
            f"[2024-07-19T12:00:00Z] INFO - User accessed {ep0} | response_ms={r0} load={a/100:.2f}",
            f"[2024-07-19T12:03:00Z] INFO - User accessed {ep3} | response_ms={r3} load={b/100:.2f}",
            f"[2024-07-19T12:02:00Z] INFO - User accessed {ep2} | response_ms={r2} load= ",
            f"[2024-07-19T12:02:30Z] INFO - User accessed /api/{token}/ignored | load=0.99",
            "[2024-07-19T12:05:00Z] ERROR - Database connection failed",
        ]
        RAW.write_text("\n".join(lines) + "\n")
        if CSV.exists():
            CSV.unlink()
        run_program()

        imputed = (a + b) / 200.0
        dynamic_expected = "\n".join([
            "Timestamp,Endpoint,ResponseTimeMs,ServerLoad",
            f"2024-07-19T12:00:00Z,{ep0},{r0},{a/100:.2f}",
            f"2024-07-19T12:01:00Z,{ep1},{r1},{imputed:.2f}",
            f"2024-07-19T12:02:00Z,{ep2},{r2},{imputed:.2f}",
            f"2024-07-19T12:03:00Z,{ep3},{r3},{b/100:.2f}",
            f"2024-07-19T12:04:00Z,{ep4},{r4},{c/100:.2f}",
        ])
        assert_csv_lines(dynamic_expected)
    finally:
        RAW.write_text(ORIGINAL_RAW)
        if BINARY.exists():
            subprocess.run([str(BINARY)], cwd="/home/user", timeout=15,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
