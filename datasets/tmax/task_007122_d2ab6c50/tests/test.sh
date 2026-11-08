#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import ast
import stat
import sys
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/join_data.py"
USERS_PATH = "/home/user/users.csv"
SCORES_PATH = "/home/user/scores.csv"
MERGED_PATH = "/home/user/merged.csv"


def test_merged_csv_exists():
    merged_path = "/home/user/merged.csv"
    assert os.path.isfile(merged_path), f"Output file {merged_path} does not exist. Did you run the script?"


def test_merged_csv_content():
    merged_path = "/home/user/merged.csv"

    expected_rows = [
        ["user_id", "name", "age", "score1", "score2", "total_score"],
        ["1", "Alice", "25", "10", "20", "30"],
        ["2", "Bob", "30", "15", "15", "30"],
        ["3", "Charlie", "22", "0", "0", "0"],
        ["4", "Diana", "28", "30", "40", "70"]
    ]

    with open(merged_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert actual_rows == expected_rows, f"Content of {merged_path} does not match the expected output. Make sure you performed a left join, filled NAs with 0, calculated total_score, and converted numerical columns to integers."


def test_no_floats_in_merged_csv():
    merged_path = "/home/user/merged.csv"
    with open(merged_path, "r") as f:
        content = f.read()

    assert ".0" not in content, f"Found '.0' in {merged_path}. Ensure that pandas integer columns are strictly cast to integers, not floats."


def test_script_exists_and_is_python():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular file."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), f"{SCRIPT_PATH} is empty."
    ast.parse(source, filename=SCRIPT_PATH)


def test_script_executes_pipeline_on_new_inputs_with_pandas():
    original = {}
    for path in (USERS_PATH, SCORES_PATH, MERGED_PATH):
        original[path] = open(path, "rb").read() if os.path.exists(path) else None

    base = secrets.randbelow(800000) + 100000
    ids = [base + 11, base + 23, base + 37, base + 49]
    ages = [19 + secrets.randbelow(20) for _ in ids]
    scores = [
        (7 + secrets.randbelow(40), 11 + secrets.randbelow(40)),
        (13 + secrets.randbelow(40), 17 + secrets.randbelow(40)),
        (19 + secrets.randbelow(40), 23 + secrets.randbelow(40)),
    ]
    names = [f"User_{secrets.token_hex(4)}" for _ in ids]
    extra_id = base + 999

    try:
        with open(USERS_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "name", "age"])
            for uid, name, age in zip(ids, names, ages):
                writer.writerow([uid, name, age])

        with open(SCORES_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "score1", "score2"])
            writer.writerow([extra_id, 91, 92])
            writer.writerow([ids[3], scores[2][0], scores[2][1]])
            writer.writerow([ids[0], scores[0][0], scores[0][1]])
            writer.writerow([ids[1], scores[1][0], scores[1][1]])

        if os.path.exists(MERGED_PATH):
            os.remove(MERGED_PATH)

        with tempfile.TemporaryDirectory() as hook_dir:
            log_path = os.path.join(hook_dir, "pandas_reads.log")
            hook = r'''
import os
import pandas as _pd

_log_path = os.environ.get("PANDAS_READ_LOG")

def _record(target):
    if target is None or not _log_path:
        return
    try:
        target = os.path.abspath(os.fspath(target))
    except TypeError:
        return
    with open(_log_path, "a", encoding="utf-8") as _log:
        _log.write(target + "\\n")

def _wrap(func):
    def wrapped(*args, **kwargs):
        target = args[0] if args else kwargs.get("filepath_or_buffer")
        _record(target)
        return func(*args, **kwargs)
    return wrapped

for _name in ("read_csv", "read_table"):
    if hasattr(_pd, _name):
        _original = getattr(_pd, _name)
        _wrapped = _wrap(_original)
        setattr(_pd, _name, _wrapped)
        try:
            setattr(_pd.io.parsers, _name, _wrapped)
        except (AttributeError, TypeError):
            pass
        try:
            setattr(_pd.io.parsers.readers, _name, _wrapped)
        except (AttributeError, TypeError):
            pass
'''
            with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
                f.write(hook)

            env = os.environ.copy()
            env["PANDAS_READ_LOG"] = log_path
            env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
            result = subprocess.run(
                [sys.executable, SCRIPT_PATH],
                cwd="/home/user",
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )

            assert result.returncode == 0, (
                f"{SCRIPT_PATH} failed when executed on new inputs.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(MERGED_PATH), "Executing join_data.py did not create merged.csv."

            reads = []
            if os.path.exists(log_path):
                with open(log_path, "r", encoding="utf-8") as f:
                    reads = [line.strip() for line in f if line.strip()]
            assert os.path.abspath(USERS_PATH) in reads, "join_data.py must read users.csv using pandas."
            assert os.path.abspath(SCORES_PATH) in reads, "join_data.py must read scores.csv using pandas."

        expected_rows = [
            ["user_id", "name", "age", "score1", "score2", "total_score"],
            [str(ids[0]), names[0], str(ages[0]), str(scores[0][0]), str(scores[0][1]), str(sum(scores[0]))],
            [str(ids[1]), names[1], str(ages[1]), str(scores[1][0]), str(scores[1][1]), str(sum(scores[1]))],
            [str(ids[2]), names[2], str(ages[2]), "0", "0", "0"],
            [str(ids[3]), names[3], str(ages[3]), str(scores[2][0]), str(scores[2][1]), str(sum(scores[2]))],
        ]
        with open(MERGED_PATH, "r", newline="", encoding="utf-8") as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows, (
            "Executing join_data.py on new inputs did not perform the required left join, "
            "missing-value fill, total calculation, column ordering, and integer formatting."
        )
        assert ".0" not in open(MERGED_PATH, "r", encoding="utf-8").read()
    finally:
        for path, data in original.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
