#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shutil
import string
import subprocess
from decimal import Decimal

import pytest

SCRIPT = "/home/user/find_fraud.sh"
USERS = "/home/user/users.csv"
TRANSACTIONS = "/home/user/transactions.csv"
OUTPUT = "/home/user/suspects.json"
DB = "/home/user/kuzu_db"
VENV_PYTHON = "/home/user/venv/bin/python"


def test_find_fraud_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."


def test_venv_and_kuzu_db_exist():
    assert os.path.isdir("/home/user/venv"), "The virtual environment directory /home/user/venv was not created."
    assert os.path.isdir(DB), f"The Kuzu database directory {DB} was not created."


def test_suspects_json_content():
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} does not exist."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {OUTPUT} does not contain valid JSON.")

    assert isinstance(data, list), f"The content of {OUTPUT} should be a JSON array (list)."
    expected_suspects = [
        "Frank White",
        "Grace Hall",
        "Harry King",
        "Jack Black",
    ]
    assert data == expected_suspects, f"The suspects list in {OUTPUT} does not match the expected output. Got: {data}"


def expected_names(users_path, transactions_path, start, minimum):
    with open(users_path, newline="", encoding="utf-8") as f:
        names = {row["user_id"]: row["name"] for row in csv.DictReader(f)}
    with open(transactions_path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    first_hops = [
        row["receiver_id"]
        for row in rows
        if row["sender_id"] == start and Decimal(row["amount"]) > minimum
    ]
    destinations = {
        names[row["receiver_id"]]
        for middle in first_hops
        for row in rows
        if row["sender_id"] == middle
        and Decimal(row["amount"]) > minimum
        and row["receiver_id"] != start
    }
    return sorted(destinations)


def run_tool(start, minimum):
    if os.path.exists(DB):
        shutil.rmtree(DB)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [SCRIPT, start, str(minimum)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"find_fraud.sh failed for arguments {start!r}, {minimum!r}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The script did not create /home/user/suspects.json."
    with open(OUTPUT, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"The script produced invalid JSON: {exc}")
    assert isinstance(data, list), "The generated JSON must be an array."
    return data


def assert_real_kuzu_database(expected_user_count, expected_tx_count):
    assert os.path.isfile(VENV_PYTHON), "The requested virtual environment has no Python interpreter."
    probe = r'''
import json
import kuzu
import sys

db = kuzu.Database(sys.argv[1], read_only=True)
conn = kuzu.Connection(db)

def scalar(query):
    result = conn.execute(query)
    assert result.has_next(), "query returned no row"
    return int(result.get_next()[0])

print(json.dumps({
    "users": scalar("MATCH (u:User) RETURN count(u)"),
    "relationships": scalar("MATCH (a:User)-[r:Transferred]->(b:User) RETURN count(r)"),
}))
'''
    result = subprocess.run(
        [VENV_PYTHON, "-c", probe, DB],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        "The generated kuzu_db is not a usable Kùzu database with User nodes and "
        f"Transferred relationships.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    counts = json.loads(result.stdout.strip().splitlines()[-1])
    assert counts == {"users": expected_user_count, "relationships": expected_tx_count}


def test_script_executes_with_dynamic_arguments_and_uses_kuzu_cypher():
    with open(SCRIPT, encoding="utf-8", errors="replace") as f:
        source = f.read()
    lowered = source.lower()
    assert "kuzu" in lowered, "The tool does not invoke the Kùzu Python package."
    assert re.search(r"\bmatch\b", source, re.I), "No Cypher MATCH query was found in the tool."
    assert re.search(r"\bUser\b", source), "The required User node table is not referenced."
    assert re.search(r"\bTransferred\b", source), "The required Transferred relationship table is not referenced."
    assert re.search(r"\$[A-Za-z_][A-Za-z0-9_]*", source), "The Cypher query does not contain parameters."
    assert "amount" in lowered, "The transaction amount is not used by the tool."

    with open(USERS, "rb") as f:
        original_users = f.read()
    with open(TRANSACTIONS, "rb") as f:
        original_transactions = f.read()

    token = "".join(random.SystemRandom().choices(string.ascii_uppercase + string.digits, k=10))
    a, b, d, c1, c2, e, bad, x = [f"R{token}{i}" for i in range(8)]
    names = {
        a: f"Origin {token}",
        b: f"Bridge Z {token}",
        d: f"Bridge A {token}",
        c1: f"Zulu {token}",
        c2: f"Alpha {token}",
        e: f"Low Bridge {token}",
        bad: f"Excluded {token}",
        x: f"Other Origin {token}",
    }
    threshold = Decimal(random.SystemRandom().randint(613, 947))
    txs = [
        ("Q1", a, b, threshold + 100),
        ("Q2", b, c1, threshold + 10),
        ("Q3", a, d, threshold + 200),
        ("Q4", d, c1, threshold + 20),
        ("Q5", b, c2, threshold),
        ("Q6", b, a, threshold + 30),
        ("Q7", a, e, threshold - 1),
        ("Q8", e, bad, threshold + 400),
        ("Q9", x, b, threshold + 300),
    ]

    try:
        with open(USERS, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["user_id", "name", "age"])
            for uid, name in names.items():
                writer.writerow([uid, name, 40])
        with open(TRANSACTIONS, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["tx_id", "sender_id", "receiver_id", "amount"])
            for txid, sender, receiver, amount in txs:
                writer.writerow([txid, sender, receiver, f"{amount:.2f}"])

        expected = expected_names(USERS, TRANSACTIONS, a, threshold)
        actual = run_tool(a, threshold)
        assert actual == expected, f"Dynamic 2-hop result was incorrect. Expected {expected}, got {actual}."
        assert actual == sorted(set(actual)), "Results must be sorted alphabetically and deduplicated."
        assert_real_kuzu_database(len(names), len(txs))

        second_minimum = threshold - 50
        expected_second = expected_names(USERS, TRANSACTIONS, x, second_minimum)
        actual_second = run_tool(x, second_minimum)
        assert actual_second == expected_second, (
            f"The tool did not honor its supplied user/minimum arguments. "
            f"Expected {expected_second}, got {actual_second}."
        )
        assert_real_kuzu_database(len(names), len(txs))
    finally:
        with open(USERS, "wb") as f:
            f.write(original_users)
        with open(TRANSACTIONS, "wb") as f:
            f.write(original_transactions)
        if os.path.exists(DB):
            shutil.rmtree(DB)
        subprocess.run(
            [SCRIPT, "U1005", "500.00"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
            check=False,
        )

    with open(OUTPUT, encoding="utf-8") as f:
        final_data = json.load(f)
    assert final_data == ["Frank White", "Grace Hall", "Harry King", "Jack Black"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
