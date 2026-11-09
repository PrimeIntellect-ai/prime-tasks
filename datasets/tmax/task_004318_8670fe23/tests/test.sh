#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

REPO = Path("/home/user/fast-det")
EXE = REPO / "fast-det"
RUNNER = REPO / "tests/test_runner.sh"
CASES = REPO / "tests/cases.csv"
SUMMARY = Path("/home/user/pr_summary.json")


def run_checked(command, *, cwd=REPO, timeout=30):
    result = subprocess.run(
        command, cwd=cwd, capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def determinant(matrix):
    size = len(matrix)
    if size == 1:
        return matrix[0][0]
    if size == 2:
        return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]
    total = 0
    for column in range(size):
        minor = [row[:column] + row[column + 1:] for row in matrix[1:]]
        total += (-1 if column % 2 else 1) * matrix[0][column] * determinant(minor)
    return total


def load_summary():
    assert SUMMARY.exists(), (
        f"The report file {SUMMARY} does not exist. Did test_runner.sh create it?"
    )
    try:
        with SUMMARY.open() as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {SUMMARY} does not contain valid JSON: {exc}")
    assert "passed" in data, "JSON report is missing the 'passed' key."
    assert "failed" in data, "JSON report is missing the 'failed' key."
    assert "total" in data, "JSON report is missing the 'total' key."
    return data


def test_clean_make_builds_real_executable():
    run_checked(["make", "clean"])
    run_checked(["make", "fast-det"])

    assert EXE.exists(), (
        "The executable /home/user/fast-det/fast-det does not exist. "
        "Did the Makefile build it?"
    )
    assert EXE.is_file(), f"Expected {EXE} to be a file."
    assert os.access(EXE, os.X_OK), f"Expected {EXE} to be executable."
    with EXE.open("rb") as handle:
        assert handle.read(4) == b"\x7fELF", "fast-det must be a compiled ELF executable."


def test_fast_det_runs_and_handles_derived_matrices():
    # Preserve the original verifier's identity-matrix assertion.
    result = subprocess.run(
        [str(EXE), "2", "1", "0", "0", "1"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"fast-det failed to run. Stderr: {result.stderr}"
    assert result.stdout.strip() == "1", (
        "Expected determinant of 2x2 identity matrix to be 1, "
        f"got {result.stdout.strip()!r}"
    )

    rng = secrets.SystemRandom()
    for _ in range(12):
        size = rng.choice([1, 2, 3, 4])
        matrix = [[rng.randint(-7, 7) for _ in range(size)] for _ in range(size)]
        expected = determinant(matrix)
        elements = [str(value) for row in matrix for value in row]
        result = subprocess.run(
            [str(EXE), str(size), *elements],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"fast-det failed for {matrix!r}. Stderr: {result.stderr}"
        )
        assert result.stdout.strip() == str(expected), (
            f"For matrix {matrix!r}, expected determinant {expected}, "
            f"got {result.stdout.strip()!r}"
        )


def test_original_cases_generate_required_report():
    assert RUNNER.is_file(), f"Missing test orchestrator {RUNNER}."
    if SUMMARY.exists():
        SUMMARY.unlink()
    run_checked(["bash", str(RUNNER)])
    data = load_summary()
    assert data["passed"] == 3, f"Expected 3 passed tests, got {data['passed']}."
    assert data["failed"] == 0, f"Expected 0 failed tests, got {data['failed']}."
    assert data["total"] == 3, f"Expected 3 total tests, got {data['total']}."


def test_runner_parses_and_executes_dynamic_cases():
    rng = secrets.SystemRandom()
    count = rng.randint(6, 9)
    rows = []
    expected_calls = []
    passed = 0
    failed = 0

    for case_id in range(100, 100 + count):
        size = rng.choice([1, 2, 3, 4])
        matrix = [[rng.randint(-6, 6) for _ in range(size)] for _ in range(size)]
        actual = determinant(matrix)
        elements = [str(value) for row in matrix for value in row]
        # Include both passing and deliberately failing expectations so the
        # report must reflect actual comparisons rather than merely line count.
        if case_id % 3 == 0:
            expected = actual + rng.choice([1, 2, 5])
            failed += 1
        else:
            expected = actual
            passed += 1
        rows.append(f"{case_id},{size},{' '.join(elements)},{expected}")
        expected_calls.append([str(size), *elements])

    original_cases = CASES.read_bytes()
    real_exe = REPO / ".fast-det.verifier-real"
    call_log = REPO / ".fast-det.verifier-calls"

    assert not real_exe.exists(), f"Unexpected verifier temporary file: {real_exe}"
    try:
        CASES.write_text("\n".join(rows) + "\n")
        if call_log.exists():
            call_log.unlink()

        os.replace(EXE, real_exe)
        EXE.write_text(
            "#!/bin/bash\n"
            f"printf '%s\\t' \"$@\" >> {call_log}\n"
            f"printf '\\n' >> {call_log}\n"
            f"exec {real_exe} \"$@\"\n"
        )
        EXE.chmod(EXE.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

        if SUMMARY.exists():
            SUMMARY.unlink()
        run_checked(["bash", str(RUNNER)])
        data = load_summary()
        assert set(data) == {"passed", "failed", "total"}, (
            f"Report must contain exactly passed, failed, and total; got {data!r}"
        )
        assert data == {"passed": passed, "failed": failed, "total": count}, (
            f"Incorrect report for dynamic CSV cases: {data!r}"
        )

        assert call_log.exists(), "test_runner.sh did not invoke ./fast-det."
        calls = []
        for line in call_log.read_text().splitlines():
            fields = line.split("\t")
            if fields and fields[-1] == "":
                fields.pop()
            calls.append(fields)
        assert calls == expected_calls, (
            "test_runner.sh did not pass each CSV size and flattened matrix "
            f"to ./fast-det correctly. Expected {expected_calls!r}, got {calls!r}"
        )
    finally:
        CASES.write_bytes(original_cases)
        if EXE.exists():
            EXE.unlink()
        if real_exe.exists():
            os.replace(real_exe, EXE)
        if call_log.exists():
            call_log.unlink()


def test_c_code_fixed():
    c_path = REPO / "src/determinant.c"
    content = c_path.read_text()
    # Preserve the original assertion and additionally require a real directive.
    assert "<math.h>" in content, "The file determinant.c does not seem to include <math.h>."
    assert re.search(r"^\s*#\s*include\s*<math\.h>\s*$", content, re.MULTILINE), (
        "determinant.c must contain an actual #include <math.h> directive."
    )


def test_makefile_fixed():
    makefile_path = REPO / "Makefile"
    content = makefile_path.read_text()
    # Preserve the original assertion and reject an occurrence only in a comment.
    assert "-lm" in content, "The Makefile does not seem to link the math library (-lm)."
    active_lines = [line for line in content.splitlines() if not line.lstrip().startswith("#")]
    assert any(re.search(r"(^|\s)-lm($|\s)", line) for line in active_lines), (
        "The Makefile must use -lm in an active variable or recipe line."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
