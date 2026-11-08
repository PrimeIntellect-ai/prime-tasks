#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

HOME = "/home/user"
RAW = f"{HOME}/raw_data.txt"
ETL = f"{HOME}/etl.sh"
C_SOURCE = f"{HOME}/tune.c"
TUNE = f"{HOME}/tune"
CLEAN = f"{HOME}/clean_data.csv"
BEST = f"{HOME}/best_lambda.txt"
CANDIDATES = [0.1, 1.0, 10.0, 100.0]


def test_clean_data_csv():
    assert os.path.isfile(CLEAN), f"The clean data file is missing at {CLEAN}"
    with open(CLEAN, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 50, f"Expected exactly 50 lines in {CLEAN}, but found {len(lines)}."
    for i, line in enumerate(lines):
        match = re.match(r'^-?\d+(\.\d+)?,-?\d+(\.\d+)?$', line)
        assert match is not None, f"Line {i+1} in {CLEAN} is not in the correct format 'X,Y': {line}"


def test_tune_executable_exists():
    assert os.path.isfile(TUNE), f"The compiled executable is missing at {TUNE}"
    assert os.access(TUNE, os.X_OK), f"The file at {TUNE} is not executable."


def test_best_lambda_output():
    assert os.path.isfile(BEST), f"The output file is missing at {BEST}"
    with open(BEST, "r") as f:
        content = f.read().strip()
    assert content == "0.1", f"Expected best lambda to be '0.1', but got '{content}'"


def expected_etl(raw_text):
    result = []
    pattern = re.compile(r'\bSTATUS=(OK|ERROR)\b.*?\bX=([^\s]+)\s+Y=([^\s]+)\b')
    for line in raw_text.splitlines():
        match = pattern.search(line)
        if match and match.group(1) == "OK":
            result.append(f"{match.group(2)},{match.group(3)}")
    return result


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def cv_scores(rows):
    scores = []
    for lam in CANDIDATES:
        total = 0.0
        for fold in range(5):
            lo, hi = fold * 10, (fold + 1) * 10
            training = rows[:lo] + rows[hi:]
            numerator = sum(x * y for x, y in training)
            denominator = sum(x * x for x, _ in training) + lam
            w = numerator / denominator
            total += sum((y - w * x) ** 2 for x, y in rows[lo:hi])
        scores.append(total)
    return scores


def make_hidden_cases():
    rng = random.SystemRandom()
    cases = []
    for target_index, target in enumerate(CANDIDATES):
        for _ in range(6000):
            sigma = math.sqrt(target) * rng.uniform(0.75, 1.25)
            generated = []
            for _row in range(50):
                x = rng.gauss(0.0, 1.0)
                y = x + rng.gauss(0.0, sigma)
                # Calculate from exactly the decimal values supplied to the program.
                generated.append((float(f"{x:.10f}"), float(f"{y:.10f}")))
            scores = cv_scores(generated)
            winner = min(range(4), key=lambda i: scores[i])
            ordered = sorted(scores)
            margin = ordered[1] - ordered[0]
            if winner == target_index and margin > max(1e-7, abs(ordered[0]) * 1e-5):
                cases.append(generated)
                break
        else:
            raise AssertionError(f"Could not construct a stable hidden case for lambda {target}")
    return cases


def run_tuner(executable, rows, expected):
    with open(CLEAN, "w") as f:
        for x, y in rows:
            f.write(f"{x:.10f},{y:.10f}\n")
    try:
        os.remove(BEST)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [executable], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(BEST), f"{executable} did not create {BEST}"
    with open(BEST, "r") as f:
        actual = f.read().strip()
    assert actual == f"{expected:.1f}", (
        f"For a hidden dataset, expected lambda {expected:.1f}, got {actual!r}"
    )


def test_etl_and_cross_validation_implementations():
    assert os.path.isfile(ETL), f"The ETL script is missing at {ETL}"
    assert os.path.isfile(C_SOURCE), f"The C source file is missing at {C_SOURCE}"
    with open(C_SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r'^\s*#\s*include\s*[<\"]math\.h[>\"]', source, re.MULTILINE), \
        "tune.c must include math.h"
    with open(TUNE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The tune executable must be a compiled native executable"

    saved = {}
    for path in (RAW, CLEAN, BEST):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()

    rebuilt = f"/tmp/tune_verified_{os.getpid()}"
    try:
        rng = random.SystemRandom()
        raw_lines = []
        expected = []
        ok_count = 0
        for i in range(67):
            is_error = i % 4 == 1
            x = f"{rng.uniform(-50, 50):.6f}"
            y = f"{rng.uniform(-100, 100):.6f}"
            status = "ERROR" if is_error else "OK"
            raw_lines.append(f"[12:{i % 60:02d}:00] STATUS={status} X={x} Y={y} ID={1000+i}")
            if not is_error:
                expected.append(f"{x},{y}")
                ok_count += 1
        assert ok_count == 50
        with open(RAW, "w") as f:
            f.write("\n".join(raw_lines) + "\n")
        result = subprocess.run(
            ["/bin/bash", ETL], cwd=HOME, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert result.returncode == 0, f"etl.sh failed: {result.stderr}"
        assert read_nonempty_lines(CLEAN) == expected, \
            "etl.sh did not filter and extract the hidden raw log correctly and in order"

        # Also execute the ETL script against the supplied raw file and derive its answer.
        with open(RAW, "wb") as f:
            f.write(saved[RAW])
        original_raw = saved[RAW].decode()
        result = subprocess.run(
            ["/bin/bash", ETL], cwd=HOME, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert result.returncode == 0, f"etl.sh failed on raw_data.txt: {result.stderr}"
        assert read_nonempty_lines(CLEAN) == expected_etl(original_raw), \
            "clean_data.csv does not match raw_data.txt"

        compile_result = subprocess.run(
            ["gcc", "-O2", "-o", rebuilt, C_SOURCE, "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, f"tune.c does not compile: {compile_result.stderr}"

        for rows in make_hidden_cases():
            scores = cv_scores(rows)
            expected_lambda = CANDIDATES[min(range(4), key=lambda i: scores[i])]
            # Exercise both the submitted executable and a fresh build of submitted tune.c.
            run_tuner(TUNE, rows, expected_lambda)
            run_tuner(rebuilt, rows, expected_lambda)
    finally:
        for path, content in saved.items():
            with open(path, "wb") as f:
                f.write(content)
        for path in (RAW, CLEAN, BEST):
            if path not in saved and os.path.exists(path):
                os.remove(path)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
