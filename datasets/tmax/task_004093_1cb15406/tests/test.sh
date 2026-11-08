#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile


def run_script(script_path, path):
    try:
        return subprocess.run(
            ["bash", script_path, path],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Validator timed out on {path}")


def oracle(rows, users):
    if not rows:
        return 1
    for row in rows:
        if len(row) != 4:
            return 1
        user_id, score_text, x_text, y_text = row
        if re.fullmatch(r"[0-9]+", user_id) is None:
            return 1
        if users.get(user_id) != "active":
            return 1
        try:
            score = float(score_text)
            x = float(x_text)
            y = float(y_text)
        except ValueError:
            return 1
        if not all(math.isfinite(v) for v in (score, x, y)):
            return 1
        if not score > 2.50:
            return 1
        norm = math.hypot(x, y)
        if not (norm > 0.9 and norm < 1.1):
            return 1
    return 0


def test_filter_data_script():
    script_path = "/home/user/filter_data.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.R_OK), f"Script {script_path} is not readable."

    # Preserve the original checks over the image's supplied examples.
    clean_files = glob.glob("/app/data/clean/*.csv")
    evil_files = glob.glob("/app/data/evil/*.csv")

    assert len(clean_files) > 0, "No clean files found in /app/data/clean/"
    assert len(evil_files) > 0, "No evil files found in /app/data/evil/"

    clean_failed = []
    for f in clean_files:
        result = run_script(script_path, f)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_passed = []
    for f in evil_files:
        result = run_script(script_path, f)
        if result.returncode == 0:
            evil_passed.append(os.path.basename(f))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_passed:
        error_msgs.append(f"{len(evil_passed)} of {len(evil_files)} evil bypassed: {', '.join(evil_passed)}")
    assert not clean_failed and not evil_passed, " | ".join(error_msgs)

    # Exercise unseen, neutrally named files and randomized users added to the
    # actual join source. Expected results are computed from the schema rules.
    db_path = "/app/db/users.csv"
    original_db = open(db_path, "rb").read()
    temp_dir = tempfile.mkdtemp(prefix="csv_validation_", dir="/tmp")
    rng = random.SystemRandom()

    existing_ids = set()
    with open(db_path, newline="") as fh:
        for row in csv.reader(fh):
            if len(row) == 3:
                existing_ids.add(row[0])

    def fresh_id():
        while True:
            candidate = str(rng.randrange(200000, 999999999))
            if candidate not in existing_ids:
                existing_ids.add(candidate)
                return candidate

    active_ids = [fresh_id() for _ in range(4)]
    inactive_ids = [fresh_id() for _ in range(3)]
    unknown_id = fresh_id()

    def valid_row(uid):
        score = rng.uniform(2.60, 9.0)
        radius = rng.uniform(0.93, 1.07)
        angle = rng.uniform(0.0, 2.0 * math.pi)
        return [uid, f"{score:.6f}", f"{radius * math.cos(angle):.8f}", f"{radius * math.sin(angle):.8f}"]

    try:
        with open(db_path, "a", newline="") as fh:
            for uid in active_ids:
                fh.write(f"{uid},active,2024-01-01\n")
            for uid in inactive_ids:
                fh.write(f"{uid},inactive,2024-01-02\n")

        users = {}
        with open(db_path, newline="") as fh:
            for row in csv.reader(fh):
                if len(row) == 3:
                    users[row[0]] = row[1]

        cases = []
        for _ in range(12):
            cases.append([valid_row(rng.choice(active_ids)) for _ in range(rng.randint(1, 4))])

        base = valid_row(active_ids[0])
        cases.extend([
            [[active_ids[0] + ".0", base[1], base[2], base[3]]],
            [["NaN", base[1], base[2], base[3]]],
            [valid_row(rng.choice(inactive_ids))],
            [valid_row(unknown_id)],
            [[active_ids[0], "2.50", "1", "0"]],
            [[active_ids[0], "1.75", "1", "0"]],
            [[active_ids[0], "3.0", "0.9", "0"]],
            [[active_ids[0], "3.0", "1.1", "0"]],
            [[active_ids[0], "3.0", "0.3", "0.4"]],
            [[active_ids[0], "3.0", "1.4", "0"]],
            [[active_ids[0], "3.0", "not-a-number", "0"]],
            [[active_ids[0], "3.0", "1.0"]],
            [[active_ids[0], "3.0", "1.0", "0", "extra"]],
            [valid_row(active_ids[1]), valid_row(inactive_ids[0])],
        ])

        mutation_kinds = ["decimal_id", "inactive", "unknown", "score", "low_norm", "high_norm"]
        for _ in range(18):
            row = valid_row(rng.choice(active_ids))
            kind = rng.choice(mutation_kinds)
            if kind == "decimal_id":
                row[0] += ".0"
            elif kind == "inactive":
                row[0] = rng.choice(inactive_ids)
            elif kind == "unknown":
                row[0] = unknown_id
            elif kind == "score":
                row[1] = f"{rng.uniform(-5.0, 2.5):.6f}"
            elif kind == "low_norm":
                row[2], row[3] = "0.1", "0.2"
            elif kind == "high_norm":
                row[2], row[3] = "1.3", "0.7"
            cases.append([row])

        rng.shuffle(cases)
        failures = []
        for rows in cases:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".csv")
            with open(path, "w", newline="") as fh:
                csv.writer(fh, lineterminator="\n").writerows(rows)
            expected = oracle(rows, users)
            result = run_script(script_path, path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected exit {expected}, got {result.returncode}; rows={rows!r}"
                )

        assert not failures, "Generated validation failures: " + " | ".join(failures)
    finally:
        with open(db_path, "wb") as fh:
            fh.write(original_db)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
