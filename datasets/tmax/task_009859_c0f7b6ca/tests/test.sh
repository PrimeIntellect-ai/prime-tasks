#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP

import pytest

PROFILER = "/home/user/profiler"
EVALUATE = "/home/user/evaluate.sh"
SUMMARY = "/home/user/summary.log"


def run_command(command, timeout=10):
    return subprocess.run(
        command,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def read_report():
    assert os.path.isfile(SUMMARY), f"Report {SUMMARY} is missing."
    with open(SUMMARY, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def fmt(value):
    return str(value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def make_case(want_hypothesis):
    while True:
        if want_hypothesis:
            row1 = [120 + secrets.randbelow(81) for _ in range(5)]
            row8 = [15 + secrets.randbelow(16) for _ in range(5)]
        else:
            row1 = [80 + secrets.randbelow(61) for _ in range(5)]
            row8 = [35 + secrets.randbelow(26) for _ in range(5)]

        mean1 = Decimal(sum(row1)) / Decimal(50)
        mean8 = Decimal(sum(row8)) / Decimal(50)
        speedup = mean1 / mean8

        # Avoid exact half-cent rounding ties and ensure the test distinguishes
        # a real mean from simply selecting the first matrix element.
        scaled = speedup * Decimal(100)
        fraction = scaled - scaled.to_integral_value(rounding=ROUND_FLOOR)
        if fraction == Decimal("0.5"):
            continue
        if (speedup > Decimal(4)) != want_hypothesis:
            continue
        if mean1 == Decimal(row1[0]) / Decimal(10):
            continue
        if mean8 == Decimal(row8[0]) / Decimal(10):
            continue

        middle1 = [50 + secrets.randbelow(31) for _ in range(5)]
        middle2 = [25 + secrets.randbelow(21) for _ in range(5)]
        rows = [row1, middle1, middle2, row8]
        expected = [
            f"Mean 1-thread: {fmt(mean1)}",
            f"Mean 8-thread: {fmt(mean8)}",
            f"Speedup: {fmt(speedup)}",
            f"Hypothesis Met: {'YES' if want_hypothesis else 'NO'}",
        ]
        return rows, expected


def install_mock_profiler(rows, marker):
    matrix = "\n".join(" ".join(f"{Decimal(v) / Decimal(10):.1f}" for v in row) for row in rows)
    script = f'''#!/bin/bash
if [ "$#" -ne 1 ] || [ "$1" != "5" ]; then
    exit 42
fi
printf '%s\n' "$1" > {marker!r}
cat <<'MATRIX_EOF'
{matrix}
MATRIX_EOF
'''
    with open(PROFILER, "w") as f:
        f.write(script)
    os.chmod(PROFILER, 0o755)


def test_profiler_executable_exists():
    path = "/home/user/profiler"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the C file?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."

    result = run_command([path, "5"])
    assert result.returncode == 0, f"Compiled profiler failed: {result.stderr}"
    expected = [
        ["10.0", "10.2", "9.8", "10.1", "9.9"],
        ["5.5", "5.6", "5.4", "5.5", "5.5"],
        ["3.0", "3.1", "2.9", "3.0", "3.0"],
        ["2.0", "2.1", "1.9", "2.0", "2.0"],
    ]
    actual = [line.split() for line in result.stdout.strip().splitlines()]
    assert actual == expected, "The compiled profiler does not produce the profiler.c matrix for 5 trials."


def test_evaluate_script_exists():
    path = "/home/user/evaluate.sh"
    assert os.path.isfile(path), f"Script {path} is missing."


def test_evaluate_script_executes_profiler_and_calculates_results():
    fd, backup = tempfile.mkstemp(prefix="profiler-backup-")
    os.close(fd)
    shutil.copy2(PROFILER, backup)
    marker = f"/tmp/profiler-called-{os.getpid()}"

    try:
        for want_hypothesis in (False, True):
            rows, expected = make_case(want_hypothesis)
            install_mock_profiler(rows, marker)
            if os.path.exists(marker):
                os.unlink(marker)
            if os.path.exists(SUMMARY):
                os.unlink(SUMMARY)

            result = run_command(["/bin/bash", EVALUATE])
            assert result.returncode == 0, (
                f"evaluate.sh failed with exit code {result.returncode}: {result.stderr}"
            )
            assert os.path.isfile(marker), "evaluate.sh did not execute /home/user/profiler."
            with open(marker, "r") as f:
                assert f.read().strip() == "5", "evaluate.sh did not invoke the profiler with argument 5."
            assert read_report() == expected, "evaluate.sh did not derive the report from the profiler matrix."
    finally:
        shutil.copy2(backup, PROFILER)
        os.unlink(backup)
        if os.path.exists(marker):
            os.unlink(marker)

    if os.path.exists(SUMMARY):
        os.unlink(SUMMARY)
    result = run_command(["/bin/bash", EVALUATE])
    assert result.returncode == 0, f"evaluate.sh failed against the compiled profiler: {result.stderr}"


def test_summary_log_contents():
    path = "/home/user/summary.log"
    assert os.path.isfile(path), f"Report {path} is missing. Did you run the evaluate.sh script?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Mean 1-thread: 10.00",
        "Mean 8-thread: 2.00",
        "Speedup: 5.00",
        "Hypothesis Met: YES"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == 4, f"Expected 4 lines in {path}, found {len(actual_lines)}."

    for i, expected in enumerate(expected_lines):
        assert actual_lines[i] == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual_lines[i]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
