#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
import uuid
import pytest

PROJECT = "/home/user/motif_project"
PYTHON = "/home/user/venv/bin/python"
SCORER = os.path.join(PROJECT, "scorer")
OPTIMIZER = os.path.join(PROJECT, "optimize.py")
RESULT = os.path.join(PROJECT, "optimized_sequence.txt")


def expected_score(seq):
    score = 0
    for i in range(len(seq) - 2):
        if seq[i:i+3] == "ATG":
            score += 15
    for i in range(len(seq) - 1):
        if seq[i:i+2] == "CG":
            score += 7
        if seq[i:i+2] == "GC":
            score += 5
        if seq[i:i+2] == "TA":
            score -= 5
        if seq[i:i+2] == "TT":
            score -= 3
    return score


def read_and_validate_result(path):
    assert os.path.isfile(path), f"Output file not found at {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    lines = content.split("\n")
    seq_lines = [line for line in lines if line.startswith("Sequence:")]
    score_lines = [line for line in lines if line.startswith("Score:")]
    assert len(seq_lines) == 1, "File must contain exactly one line starting with 'Sequence:'"
    assert len(score_lines) == 1, "File must contain exactly one line starting with 'Score:'"

    seq = seq_lines[0].split("Sequence:", 1)[1].strip()
    assert len(seq) == 50, f"Sequence length is {len(seq)}, expected exactly 50."
    assert all(c in "ACGT" for c in seq), f"Sequence contains invalid characters: {seq}"

    score = expected_score(seq)
    assert score >= 150, f"Calculated score is {score}, expected >= 150."
    reported_score_str = score_lines[0].split("Score:", 1)[1].strip()
    try:
        reported_score = int(reported_score_str)
    except ValueError:
        pytest.fail(f"Reported score '{reported_score_str}' is not an integer.")
    assert reported_score == score, (
        f"Reported score {reported_score} does not match actual calculated score {score}."
    )
    return seq, score


def test_venv_and_numpy():
    assert os.path.isfile(PYTHON), f"Virtual environment Python not found at {PYTHON}"
    assert os.access(PYTHON, os.X_OK), f"Python at {PYTHON} is not executable"
    try:
        subprocess.run(
            [PYTHON, "-c", "import numpy"],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"numpy is not usable in /home/user/venv: {exc}")


def test_scorer_executable_and_behavior():
    assert os.path.isfile(SCORER), f"Compiled executable not found at {SCORER}"
    assert os.access(SCORER, os.X_OK), f"File at {SCORER} is not executable"
    with open(SCORER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "scorer is not a compiled ELF executable"

    rng = random.SystemRandom()
    cases = ["", "ATG", "CG", "GC", "TA", "TT", "ATG" * 16 + "AT"]
    for _ in range(24):
        length = rng.randint(1, 90)
        cases.append("".join(rng.choice("ACGT") for _ in range(length)))

    for seq in cases:
        proc = subprocess.run(
            [SCORER, seq], capture_output=True, text=True, timeout=5
        )
        assert proc.returncode == 0, f"scorer failed for a valid sequence of length {len(seq)}"
        try:
            actual = int(proc.stdout.strip())
        except ValueError:
            pytest.fail(f"scorer did not print an integer for input {seq!r}: {proc.stdout!r}")
        assert actual == expected_score(seq), (
            f"scorer returned {actual}, expected {expected_score(seq)} for {seq!r}"
        )

    invalid = "ACGTNACGT"
    proc = subprocess.run([SCORER, invalid], capture_output=True, text=True, timeout=5)
    assert proc.returncode == 0
    assert proc.stdout.strip() == "-9999", "scorer did not reject invalid DNA characters"

    proc = subprocess.run([SCORER], capture_output=True, text=True, timeout=5)
    assert proc.returncode != 0, "scorer should reject a missing sequence argument"


def test_optimized_sequence_file():
    read_and_validate_result(RESULT)


def test_optimizer_pipeline_runs_with_venv_and_uses_scorer():
    assert os.path.isfile(OPTIMIZER), f"Optimization script not found at {OPTIMIZER}"

    token = uuid.uuid4().hex
    real_scorer = os.path.join(tempfile.gettempdir(), f"scorer-real-{token}")
    call_log = os.path.join(tempfile.gettempdir(), f"scorer-calls-{token}.log")
    shutil.copy2(SCORER, real_scorer)

    wrapper = f'''#!/bin/sh
printf '%s\\n' "$1" >> '{call_log}'
exec '{real_scorer}' "$@"
'''

    try:
        with open(SCORER, "w") as f:
            f.write(wrapper)
        os.chmod(SCORER, 0o755)
        if os.path.exists(RESULT):
            os.remove(RESULT)

        try:
            proc = subprocess.run(
                [PYTHON, OPTIMIZER],
                cwd=PROJECT,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("optimize.py did not finish within 180 seconds")

        assert proc.returncode == 0, (
            f"optimize.py failed under /home/user/venv/bin/python.\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
        seq, _ = read_and_validate_result(RESULT)

        assert os.path.isfile(call_log), "optimize.py never invoked ./scorer"
        with open(call_log, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        candidates = [s for s in calls if len(s) == 50 and all(c in "ACGT" for c in s)]
        distinct = set(candidates)
        assert len(distinct) >= 10, (
            "optimize.py did not exercise a Monte Carlo-style search through multiple "
            "distinct 50-base candidate sequences using ./scorer"
        )
        assert seq in distinct, "The saved optimized sequence was not evaluated by ./scorer"
    finally:
        if os.path.exists(real_scorer):
            shutil.copy2(real_scorer, SCORER)
            os.chmod(SCORER, 0o755)
            os.remove(real_scorer)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
