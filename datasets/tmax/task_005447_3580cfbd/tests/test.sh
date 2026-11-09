#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import stat
import subprocess
import tempfile
from pathlib import Path

REPO = "/home/user/metrics_pipeline"
FIXED = "/home/user/fixed_process_metrics.sh"
FAILING = "/home/user/failing_input.csv"
BAD_FILE = "/home/user/bad_commit.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=15, **kwargs)


def script_at_revision(revision):
    shown = run(["git", "-C", REPO, "show", f"{revision}:process_metrics.sh"])
    assert shown.returncode == 0, shown.stderr
    tf = tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)
    tf.write(shown.stdout)
    tf.close()
    os.chmod(tf.name, os.stat(tf.name).st_mode | stat.S_IXUSR)
    return tf.name


def run_script(script, csv_path):
    return run([script, csv_path])


def make_csv(lines):
    tf = tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, newline="")
    tf.write("\n".join(lines) + "\n")
    tf.close()
    return tf.name


def expected_average(records):
    active_values = [value for _, status, value in records if status == "active" and value is not None]
    denominator = sum(1 for value in active_values if value != 0)
    if denominator == 0:
        return 0
    # SQLite integer division truncates toward zero for these INTEGER inputs.
    return int(sum(active_values) / denominator)


def assert_correct_output(records):
    lines = []
    for row_id, status, value in records:
        encoded = "" if value is None else str(value)
        lines.append(f"{row_id},{status},{encoded}")
    path = make_csv(lines)
    try:
        result = run_script(FIXED, path)
        assert result.returncode == 0, (
            f"Fixed script failed for {lines}: rc={result.returncode}, stderr={result.stderr!r}"
        )
        expected = f"Average: {expected_average(records)}"
        assert result.stdout.strip() == expected, (
            f"Wrong result for {lines}: expected {expected!r}, got {result.stdout!r}"
        )
    finally:
        os.unlink(path)


def independently_find_first_bad_commit():
    edge = make_csv(["1,active,0", "2,active,0"])
    try:
        listing = run(["git", "-C", REPO, "rev-list", "--reverse", "v1.0..master"])
        assert listing.returncode == 0, listing.stderr
        commits = [line for line in listing.stdout.splitlines() if line]
        assert commits
        for commit in commits:
            script = script_at_revision(commit)
            try:
                if run_script(script, edge).returncode != 0:
                    return commit
            finally:
                os.unlink(script)
    finally:
        os.unlink(edge)
    raise AssertionError("No bad commit was found in v1.0..master")


def test_bad_commit_hash():
    assert os.path.isfile(BAD_FILE), f"File {BAD_FILE} does not exist."
    raw = Path(BAD_FILE).read_bytes()
    assert re.fullmatch(rb"[0-9a-f]{40}\n?", raw), (
        "bad_commit.txt must contain only one full 40-character lowercase commit hash"
    )
    student_hash = raw.decode().strip()
    truth_hash = independently_find_first_bad_commit()
    assert student_hash == truth_hash, (
        f"The commit hash in {BAD_FILE} is incorrect. Expected {truth_hash}, got {student_hash}."
    )


def test_fixed_script_exists_and_executable():
    assert os.path.isfile(FIXED), f"Fixed script {FIXED} does not exist."
    assert os.access(FIXED, os.X_OK), f"Fixed script {FIXED} is not executable."
    text = Path(FIXED).read_text(errors="replace")
    assert "sqlite3" in text and re.search(r"\bSELECT\b", text, re.IGNORECASE), (
        "The fixed pipeline must retain and repair its sqlite3 query processing."
    )


def test_failing_input_is_minimal_reproducer():
    assert os.path.isfile(FAILING), f"File {FAILING} does not exist."
    with open(FAILING, newline="") as fh:
        rows = list(csv.reader(fh))
    assert 1 <= len(rows) <= 2, "failing_input.csv must be a minimal one- or two-row reproducer"
    assert all(len(row) == 3 for row in rows), "Every reproducer row must have id,status,value"
    active_values = []
    for row in rows:
        int(row[0])
        if row[1] == "active":
            active_values.append(int(row[2]))
    assert active_values and all(value == 0 for value in active_values), (
        "The reproducer must capture the all-zero active-value edge case"
    )

    master_result = run_script(os.path.join(REPO, "process_metrics.sh"), FAILING)
    assert master_result.returncode != 0, "failing_input.csv does not reproduce the master regression"

    old_script = script_at_revision("v1.0")
    try:
        assert run_script(old_script, FAILING).returncode == 0, (
            "failing_input.csv must succeed on v1.0 to demonstrate a regression"
        )
    finally:
        os.unlink(old_script)

    fixed_result = run_script(FIXED, FAILING)
    assert fixed_result.returncode == 0, (
        f"Fixed script fails on failing_input.csv: {fixed_result.stderr}"
    )
    assert fixed_result.stdout.strip() == "Average: 0", (
        f"Wrong result for failing_input.csv: {fixed_result.stdout!r}"
    )


def test_bash_fuzzer_was_written():
    candidates = []
    for path in Path("/home/user").rglob("*"):
        if not path.is_file() or str(path) in {FIXED, os.path.join(REPO, "process_metrics.sh")}:
            continue
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        lower = text.lower()
        is_bash = text.startswith("#!/bin/bash") or text.startswith("#!/usr/bin/env bash")
        invokes_pipeline = "process_metrics.sh" in text
        generates_random = bool(re.search(r"\$RANDOM|\bshuf\b|/dev/urandom|\brandom\b", text, re.I))
        iterates = bool(re.search(r"\b(for|while|until)\b", lower))
        creates_csv_data = "active" in lower and ("," in text or "csv" in lower)
        if is_bash and invokes_pipeline and generates_random and iterates and creates_csv_data:
            candidates.append(path)
    assert candidates, (
        "No Bash fuzzer was found that generates random CSV data in a loop and feeds it to process_metrics.sh"
    )


def test_fixed_script_handles_edge_case():
    assert_correct_output([(1, "active", 0), (2, "active", 0)])


def test_fixed_script_handles_normal_case():
    assert_correct_output([(1, "active", 100), (2, "active", 200)])


def test_fixed_script_business_logic_and_generated_inputs():
    fixed_cases = [
        [(1, "active", 0), (2, "active", 100)],
        [(1, "inactive", 999), (2, "active", 25), (3, "active", 75)],
        [(1, "active", None), (2, "active", 0), (3, "active", 12)],
        [(1, "inactive", 10), (2, "pending", 20)],
        [(1, "active", -9), (2, "active", 0), (3, "active", 4)],
    ]
    for records in fixed_cases:
        assert_correct_output(records)

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    statuses = ["active", "inactive", "pending"]
    for _ in range(20):
        records = []
        for row_id in range(1, rng.randint(2, 10)):
            status = rng.choice(statuses)
            value = rng.choice([None, 0, 0, rng.randint(-500, 500)])
            records.append((row_id, status, value))
        assert_correct_output(records)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
