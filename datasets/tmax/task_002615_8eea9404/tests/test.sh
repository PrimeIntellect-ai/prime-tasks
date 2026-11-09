#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/users.csv "$backup_dir/users.csv"
cp /home/user/activity.csv "$backup_dir/activity.csv"
if [ -f /home/user/correlation_result.txt ]; then
    cp /home/user/correlation_result.txt "$backup_dir/correlation_result.txt"
    touch "$backup_dir/had_result"
fi

cleanup() {
    cp "$backup_dir/users.csv" /home/user/users.csv
    cp "$backup_dir/activity.csv" /home/user/activity.csv
    if [ -f "$backup_dir/had_result" ]; then
        cp "$backup_dir/correlation_result.txt" /home/user/correlation_result.txt
    else
        rm -f /home/user/correlation_result.txt
    fi
    rm -rf "$backup_dir" /tmp/compute_corr_verifier
}
trap cleanup EXIT

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

SOURCE = "/home/user/compute_corr.c"
RESULT = "/home/user/correlation_result.txt"
USERS = "/home/user/users.csv"
ACTIVITY = "/home/user/activity.csv"
EXECUTABLE = "/tmp/compute_corr_verifier"

# Preserve the original final-state assertions.
assert os.path.isfile(SOURCE), (
    f"The C source file {SOURCE} is missing. Did you write your code to the correct path?"
)
assert os.path.isfile(RESULT), (
    f"The output file {RESULT} is missing. Did you run your compiled program?"
)
with open(RESULT, "r") as f:
    initial_content = f.read().strip()
assert initial_content == "Correlation: -0.9888", (
    f"The contents of {RESULT} are incorrect. Expected 'Correlation: -0.9888', "
    f"got '{initial_content}'."
)

compile_result = subprocess.run(
    ["gcc", SOURCE, "-o", EXECUTABLE, "-lm"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert compile_result.returncode == 0, "compute_corr.c did not compile:\n" + compile_result.stderr
assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), "Compilation did not produce an executable"

def execute_and_check(expected):
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, "Compiled program exited unsuccessfully:\n" + completed.stderr
    assert os.path.isfile(RESULT), f"The compiled program did not create {RESULT}"
    with open(RESULT, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected '{expected}', got '{actual}'"

# Ensure the submitted C artifact itself produces the required original answer.
execute_and_check("Correlation: -0.9888")

def expected_correlation(ages, hours):
    n = len(ages)
    mean_age = sum(ages) / n
    mean_hours = sum(hours) / n
    numerator = sum((x - mean_age) * (y - mean_hours) for x, y in zip(ages, hours))
    age_ss = sum((x - mean_age) ** 2 for x in ages)
    hours_ss = sum((y - mean_hours) ** 2 for y in hours)
    corr = numerator / math.sqrt(age_ss * hours_ss)
    return f"Correlation: {corr:.4f}"

def run_case(ages, hours, first_id):
    ids = list(range(first_id, first_id + len(ages)))
    with open(USERS, "w") as f:
        f.write("user_id,age\n")
        for uid, age in zip(ids, ages):
            f.write(f"{uid},{age}\n")
    with open(ACTIVITY, "w") as f:
        f.write("user_id,hours_active\n")
        for uid, value in zip(ids, hours):
            f.write(f"{uid},{value:.2f}\n")
    execute_and_check(expected_correlation(ages, hours))

rng = secrets.SystemRandom()
for mode in ("positive", "negative", "mixed"):
    ages = rng.sample(range(18, 75), 12)
    if mode == "positive":
        hours = [round(0.37 * age + rng.uniform(-3.0, 3.0), 2) for age in ages]
    elif mode == "negative":
        hours = [round(32.0 - 0.31 * age + rng.uniform(-2.5, 2.5), 2) for age in ages]
    else:
        hours = [round(rng.uniform(1.0, 24.0), 2) for _ in ages]
    run_case(ages, hours, rng.randrange(1000, 9000))
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
