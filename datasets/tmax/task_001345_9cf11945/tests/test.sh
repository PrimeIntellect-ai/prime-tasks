#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
from decimal import Decimal

HOME = "/home/user"


def test_infer_c_exists():
    path = "/home/user/infer.c"
    assert os.path.isfile(path), f"File {path} is missing. You need to write the C program."


def test_infer_executable_exists():
    path = "/home/user/infer"
    assert os.path.isfile(path), f"Executable {path} is missing. You need to compile your C program."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_scores_csv_correct():
    path = "/home/user/scores.csv"
    assert os.path.isfile(path), f"File {path} is missing. You need to run the pipeline and save results."

    expected_content = """id,score
1,12.0
2,26.0
3,25.0
4,8.8
5,0.0"""

    with open(path, "r") as f:
        content = f.read().strip()

    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
    assert content_lines == expected_lines, f"Content of {path} does not match the expected output. Got:\n{content}"


def _find_cleaned_file():
    expected = [
        (1, 10.0, 20.0, 30.0),
        (2, 40.0, 0.0, 60.0),
        (3, 0.0, 80.0, 90.0),
        (4, 12.0, 14.0, 0.0),
        (5, 0.0, 0.0, 0.0),
    ]
    excluded = {"data.csv", "scores.csv", "weights.txt", "infer.c", "infer"}
    for name in os.listdir(HOME):
        if name in excluded:
            continue
        path = os.path.join(HOME, name)
        if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
            continue
        try:
            with open(path, "r") as f:
                lines = [line.strip() for line in f if line.strip()]
            rows = []
            for line in lines:
                fields = line.split(",")
                if len(fields) != 4:
                    raise ValueError
                rows.append((int(fields[0]), float(fields[1]), float(fields[2]), float(fields[3])))
            if rows == expected:
                return path
        except (OSError, UnicodeError, ValueError):
            pass
    raise AssertionError("No cleaned, header-free data file with missing features replaced by zero was found.")


def _assert_dynamic_output(text, expected_lines, source):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if lines and lines[0] == "id,score":
        lines = lines[1:]
    assert lines == expected_lines, f"{source} did not compute the dynamic test data correctly. Got:\n{text}"
    for line in lines:
        assert re.fullmatch(r"-?\d+,-?\d+\.\d", line), f"Bad output format from {source}: {line}"


def test_cleaned_data_and_inference_are_real():
    cleaned = _find_cleaned_file()
    weights_path = os.path.join(HOME, "weights.txt")
    scores_path = os.path.join(HOME, "scores.csv")
    rebuilt = "/tmp/infer_rebuilt"
    alternate_output = "/tmp/infer_dynamic_scores.csv"

    subprocess.run(
        ["gcc", "/home/user/infer.c", "-o", rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    choices = [Decimal(x) / Decimal(10) for x in range(-9, 10) if x != 0]
    weights = [secrets.choice(choices) for _ in range(3)]
    ids = secrets.SystemRandom().sample(range(100, 10000), 5)
    rows = []
    expected_lines = []
    for row_id in ids:
        while True:
            features = [secrets.randbelow(19) - 9 for _ in range(3)]
            score = sum((Decimal(v) * w for v, w in zip(features, weights)), Decimal(0))
            if score != 0:
                break
        rows.append((row_id, features))
        expected_lines.append(f"{row_id},{score:.1f}")

    dynamic_cleaned = "".join(
        f"{row_id},{features[0]:.1f},{features[1]:.1f},{features[2]:.1f}\n"
        for row_id, features in rows
    )
    dynamic_weights = ",".join(f"{w:.1f}" for w in weights) + "\n"

    backups = {}
    for path in (cleaned, weights_path, scores_path):
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()

    try:
        for executable in ("/home/user/infer", rebuilt):
            with open(cleaned, "w") as f:
                f.write(dynamic_cleaned)
            with open(weights_path, "w") as f:
                f.write(dynamic_weights)
            for path in (scores_path, alternate_output):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            result = subprocess.run(
                [executable, cleaned, weights_path, alternate_output],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"{executable} failed on dynamic inputs: {result.stderr}"

            candidates = []
            if result.stdout.strip():
                candidates.append((result.stdout, "standard output"))
            for path in (alternate_output, scores_path):
                if os.path.isfile(path):
                    with open(path, "r") as f:
                        candidates.append((f.read(), path))

            assert candidates, f"{executable} produced no inference output"
            errors = []
            for text, source in candidates:
                try:
                    _assert_dynamic_output(text, expected_lines, source)
                    break
                except AssertionError as exc:
                    errors.append(str(exc))
            else:
                raise AssertionError("\n".join(errors))
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
        for path in (rebuilt, alternate_output):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
