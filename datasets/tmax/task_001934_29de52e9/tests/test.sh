#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_bad_commit_identified():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_file), f"{bad_commit_file} does not exist."

    with open(bad_commit_file, "r") as f:
        student_sha = f.read().strip()

    try:
        expected_sha = subprocess.check_output(
            ["git", "rev-list", "-n", "1", "bad-commit-tag"],
            cwd="/home/user/perf_math",
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve the expected bad commit SHA from the git repository.")

    assert student_sha == expected_sha, f"Expected commit SHA {expected_sha}, but got {student_sha}"


def test_correct_sum_calculated():
    correct_sum_file = "/home/user/correct_sum.txt"
    assert os.path.isfile(correct_sum_file), f"{correct_sum_file} does not exist."

    with open(correct_sum_file, "r") as f:
        student_sum_str = f.read().strip()

    assert student_sum_str.isdigit(), f"{correct_sum_file} does not contain a valid integer."
    student_sum = int(student_sum_str)

    chunks_dir = "/home/user/perf_math/chunks"
    expected_sum = 0
    for filename in os.listdir(chunks_dir):
        if filename.endswith(".txt"):
            with open(os.path.join(chunks_dir, filename), "r") as f:
                for line in f:
                    val = line.strip()
                    if val:
                        expected_sum += int(val)

    assert student_sum == expected_sum, f"Expected sum {expected_sum}, but got {student_sum}"


def test_fixed_aggregate_script():
    fixed_script = Path("/home/user/fixed_aggregate.sh")
    assert fixed_script.is_file(), f"{fixed_script} does not exist."
    assert os.access(fixed_script, os.X_OK), f"{fixed_script} is not executable."

    content = fixed_script.read_text()

    # Preserve the original locking-mechanism assertion.
    has_flock = "flock" in content
    has_mkdir_lock = "mkdir" in content and "lock" in content.lower()
    has_lockfile = "lockfile" in content
    assert has_flock or has_mkdir_lock or has_lockfile, (
        "No safe atomic Bash locking mechanism (like flock) found in the fixed script."
    )

    repo = Path("/home/user/perf_math")
    chunks = repo / "chunks"
    backup = repo / ".verifier_chunks_backup"
    assert chunks.is_dir()
    if backup.exists():
        shutil.rmtree(backup)
    chunks.rename(backup)

    try:
        chunks.mkdir()
        # Exercise the submitted artifact on several verifier-derived datasets.
        # Replacing the normal chunks also catches scripts that hard-code the original sum.
        for trial in range(4):
            for old in chunks.iterdir():
                old.unlink()

            expected = 0
            for i in range(1, 121):
                values = [((trial + 3) * i * 17 + j * 13) % 10000 + 1 for j in range(160)]
                expected += sum(values)
                (chunks / f"chunk_{i}.txt").write_text("\n".join(map(str, values)) + "\n")

            global_sum = repo / "global_sum.txt"
            if global_sum.exists():
                global_sum.unlink()

            proc = subprocess.run(
                [str(fixed_script)],
                cwd=str(repo),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert proc.returncode == 0, (
                f"fixed_aggregate.sh failed on trial {trial}: {proc.stderr}"
            )
            assert global_sum.is_file(), "The executed script did not create global_sum.txt."
            result_text = global_sum.read_text().strip()
            assert re.fullmatch(r"-?[0-9]+", result_text), (
                f"global_sum.txt is not an integer: {result_text!r}"
            )
            assert int(result_text) == expected, (
                f"Executed fixed_aggregate.sh produced {result_text}; expected {expected} "
                f"on verifier dataset {trial}."
            )
    finally:
        if chunks.exists():
            shutil.rmtree(chunks)
        backup.rename(chunks)


def v1_divide_by_zero(path):
    with tempfile.TemporaryDirectory() as td:
        calc = Path(td) / "calc_stats_v1.sh"
        source = subprocess.check_output(
            ["git", "show", "v1.0:calc_stats.sh"],
            cwd="/home/user/perf_math",
        )
        calc.write_bytes(source)
        calc.chmod(0o755)
        proc = subprocess.run(
            [str(calc), str(path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        diagnostic = proc.stdout + "\n" + proc.stderr
        return proc.returncode != 0 and re.search(
            r"divis(?:ion|e) by (?:0|zero)", diagnostic, re.IGNORECASE
        ) is not None


def validate_crash_file(crash_file):
    if not crash_file.is_file():
        return False, "crash_input.txt was not created"
    content = crash_file.read_text()
    items = content.split()
    if not items:
        return False, "crash_input.txt is empty"
    if any(re.fullmatch(r"-?[0-9]+", item) is None for item in items):
        return False, "crash_input.txt contains a non-integer"
    numbers = [int(item) for item in items]
    if max(numbers) != min(numbers):
        return False, "the crash input does not have equal minimum and maximum"
    if not v1_divide_by_zero(crash_file):
        return False, "the input does not actually trigger v1.0's divide-by-zero error"
    return True, ""


def test_crash_input_triggers_bug():
    crash_file = Path("/home/user/crash_input.txt")
    assert crash_file.is_file(), f"{crash_file} does not exist."

    content = crash_file.read_text()
    numbers = []
    for item in content.split():
        assert item.lstrip("-").isdigit(), f"Crash input contains non-integer value: {item}"
        numbers.append(int(item))

    assert len(numbers) > 0, "Crash input file is empty."
    max_val = max(numbers)
    min_val = min(numbers)
    assert max_val == min_val, (
        f"To trigger the divide-by-zero bug, max and min must be equal. "
        f"Got max={max_val}, min={min_val}."
    )
    assert v1_divide_by_zero(crash_file), (
        "crash_input.txt does not actually make the v1.0 calc_stats.sh fail with division by zero."
    )


def test_fuzzing_script_exists_and_runs():
    excluded = {
        Path("/home/user/fixed_aggregate.sh").resolve(),
        Path("/home/user/perf_math/aggregate_logs.sh").resolve(),
        Path("/home/user/perf_math/calc_stats.sh").resolve(),
    }
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            path = Path(root) / name
            if not name.endswith(".sh") or path.resolve() in excluded:
                continue
            try:
                content = path.read_text()
            except (OSError, UnicodeDecodeError):
                continue
            # Candidate discovery is broad because the instruction did not prescribe a filename.
            if "calc_stats" in content:
                candidates.append((path, content))

    assert candidates, "No Bash fuzzing script that targets calc_stats.sh was found."

    crash_file = Path("/home/user/crash_input.txt")
    failures = []
    for path, content in candidates:
        has_random_source = any(token in content for token in ("$RANDOM", "${RANDOM", "shuf", "/dev/urandom"))
        has_loop = re.search(r"(^|[;\n])\s*(while|until|for)\b", content) is not None
        if not has_random_source or not has_loop:
            failures.append(f"{path}: does not contain random dataset generation and a loop")
            continue

        if crash_file.exists():
            crash_file.unlink()

        with tempfile.NamedTemporaryFile() as out, tempfile.NamedTemporaryFile() as trace:
            proc = subprocess.Popen(
                ["bash", "-x", str(path)],
                cwd=str(path.parent),
                stdout=out,
                stderr=trace,
                start_new_session=True,
            )
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                failures.append(f"{path}: timed out")
                continue

            trace.seek(0)
            trace_text = trace.read().decode("utf-8", errors="replace")

        traced_calc_call = any(
            line.startswith("+ ") and "calc_stats" in line
            for line in trace_text.splitlines()
        )
        if not traced_calc_call:
            failures.append(f"{path}: execution trace did not invoke calc_stats")
            continue

        valid, reason = validate_crash_file(crash_file)
        if valid:
            return
        failures.append(f"{path}: {reason}")

    pytest.fail("No submitted fuzzing script successfully reproduced the bug: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
