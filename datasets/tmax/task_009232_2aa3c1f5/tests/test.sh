#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/etl.sh"
OUTPUT_PATH = "/home/user/summary.csv"
USERS_PATH = "/home/user/data/users.csv"
PURCHASES_PATH = "/home/user/data/purchases.csv"


def run_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Script {SCRIPT_PATH} failed to execute. Error: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."


def output_lines():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()], content


def expected_from_inputs():
    with open(USERS_PATH, newline="", encoding="utf-8") as f:
        users = {row["id"]: row["region"] for row in csv.DictReader(f)}

    totals = {}
    with open(PURCHASES_PATH, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            region = users.get(row["user_id"])
            if region is not None:
                totals[region] = totals.get(region, Decimal("0.00")) + Decimal(row["amount"])

    rows = sorted(totals.items(), key=lambda item: item[1], reverse=True)
    return ["Region,TotalAmount"] + [f"{region},{amount:.2f}" for region, amount in rows]


def write_random_fixture():
    rng = random.SystemRandom()

    while True:
        suffix = secrets.token_hex(4)
        regions = [f"Region_{suffix}_{letter}" for letter in "ABCD"]
        ids = rng.sample(range(100, 10000), 11)

        users = []
        for index, user_id in enumerate(ids):
            region = regions[index % len(regions)]
            users.append((str(user_id), f"User_{suffix}_{index}", region))

        purchases = []
        totals = {region: 0 for region in regions}
        for index, (user_id, _, region) in enumerate(users[:-1]):
            for purchase_number in range(rng.randint(1, 3)):
                cents = rng.randint(1, 50000)
                totals[region] += cents
                purchases.append((
                    user_id,
                    f"{cents // 100}.{cents % 100:02d}",
                    f"2024-{(index % 12) + 1:02d}-{purchase_number + 1:02d}",
                ))

        # Include one purchase whose user is absent; an inner join must ignore it.
        purchases.append((str(rng.randint(20000, 30000)), "999.99", "2024-12-31"))

        if len(set(totals.values())) == len(regions):
            break

    rng.shuffle(users)
    rng.shuffle(purchases)

    with open(USERS_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "name", "region"])
        writer.writerows(users)

    with open(PURCHASES_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["user_id", "amount", "date"])
        writer.writerows(purchases)


def test_etl_script_exists_and_executable():
    """Check if the etl.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_etl_script_execution_and_output():
    """Run etl.sh against the original fixture and preserve its exact assertion."""
    run_script()
    actual_lines, content = output_lines()

    expected_content = """Region,TotalAmount
North,550.75
East,500.00
South,140.75
West,10.00"""
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {OUTPUT_PATH} does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{content}"
    )


def test_etl_on_unseen_inputs():
    """Exercise the ETL behavior on fixtures generated only at verification time."""
    for _ in range(3):
        write_random_fixture()
        expected_lines = expected_from_inputs()
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        run_script()
        actual_lines, content = output_lines()
        assert actual_lines == expected_lines, (
            f"ETL output was incorrect for a generated input.\n"
            f"Expected:\n{os.linesep.join(expected_lines)}\n"
            f"Actual:\n{content}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
