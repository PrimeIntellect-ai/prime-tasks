#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

SCRIPT = "/home/user/prepare_data.py"
USERS = "/home/user/users.csv"
PURCHASES = "/home/user/purchases.csv"
OUTPUT = "/home/user/fixed_mean.txt"


def run_script():
    assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} does not exist"
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist. Did the script write the output?"
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def expected_for_current_inputs():
    users = pd.read_csv(USERS)
    purchases = pd.read_csv(PURCHASES)
    df = pd.merge(users, purchases, on="user_id", how="left")
    df["amount"] = df["amount"].fillna(0)
    train, test = train_test_split(df, test_size=0.2, random_state=42)
    scaler = StandardScaler()
    scaler.fit(train[["amount"]])
    scaled_test = scaler.transform(test[["amount"]])
    return f"{float(scaled_test.mean()):.4f}"


def write_random_case(user_count, duplicate_purchase):
    rng = secrets.SystemRandom()
    start = rng.randrange(1000, 9000)
    ids = list(range(start, start + user_count))
    users = pd.DataFrame({
        "user_id": ids,
        "age": [rng.randrange(18, 75) for _ in ids],
    })

    rows = []
    for i, user_id in enumerate(ids):
        if i % 4 != 1:  # Leave some users unmatched so left join and fillna matter.
            rows.append({"user_id": user_id, "amount": rng.randrange(-50000, 90000) / 100.0})
    if duplicate_purchase:
        rows.append({"user_id": ids[3], "amount": rng.randrange(10000, 70000) / 100.0})
    rows.append({"user_id": start + user_count + 500, "amount": rng.randrange(1000, 90000) / 100.0})

    users.to_csv(USERS, index=False)
    pd.DataFrame(rows).to_csv(PURCHASES, index=False)


def test_script_splits_before_scaling_and_generates_output():
    with open(USERS, "rb") as f:
        original_users = f.read()
    with open(PURCHASES, "rb") as f:
        original_purchases = f.read()

    try:
        # Preserve the original verifier's exact assertion, but obtain the file by
        # actually executing the submitted artifact.
        content = run_script()
        assert content == "-0.1183", f"Expected '-0.1183' in {OUTPUT}, but got '{content}'. The data leak may not be fixed correctly or the calculation is wrong."

        # Exercise the script on unpredictable inputs and derive each answer
        # independently from the required join, split, fit, and transform steps.
        for user_count, duplicate_purchase in [(13, False), (21, True)]:
            write_random_case(user_count, duplicate_purchase)
            expected = expected_for_current_inputs()
            content = run_script()
            assert re.fullmatch(r"[+-]?\d+\.\d{4}", content), (
                f"{OUTPUT} must contain one numeric value with exactly 4 decimal places; got {content!r}"
            )
            assert content == expected, (
                f"Expected {expected!r} for generated inputs, got {content!r}. "
                "The scaler must be fitted only on the post-split training amount column."
            )
    finally:
        with open(USERS, "wb") as f:
            f.write(original_users)
        with open(PURCHASES, "wb") as f:
            f.write(original_purchases)
        try:
            run_script()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
