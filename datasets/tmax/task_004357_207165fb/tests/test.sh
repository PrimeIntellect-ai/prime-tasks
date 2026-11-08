#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import secrets
from collections import Counter
from pathlib import Path

SCRIPT_PATH = Path("/home/user/generate_cypher.py")
USERS_PATH = Path("/home/user/users.csv")
PURCHASES_PATH = Path("/home/user/purchases.csv")
OUT_PATH = Path("/home/user/relationships.cypher")


def run_script():
    subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        check=True,
        timeout=10,
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_python_script_modified_and_uses_matching_user_ids():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."

    original_users = USERS_PATH.read_bytes()
    original_purchases = PURCHASES_PATH.read_bytes()
    base = secrets.randbelow(800000) + 100000

    users = [
        (base + 11, "TestA"),
        (base + 22, "TestB"),
        (base + 33, "TestC"),
    ]
    purchases = [
        (base + 101, base + 22, "ItemA"),
        (base + 102, base + 11, "ItemB"),
        (base + 103, base + 33, "ItemC"),
        (base + 104, base + 11, "ItemD"),
        (base + 105, base + 44, "UnmatchedItem"),
    ]

    expected = [
        f"MATCH (u:User {{user_id: {user_id}}}), (p:Purchase {{purchase_id: {purchase_id}}}) CREATE (u)-[:BOUGHT]->(p);"
        for purchase_id, purchase_user_id, _ in purchases
        for user_id, _ in users
        if user_id == purchase_user_id
    ]

    challenge_lines = None
    try:
        USERS_PATH.write_text(
            "user_id,name\n" + "".join(f"{user_id},{name}\n" for user_id, name in users)
        )
        PURCHASES_PATH.write_text(
            "purchase_id,user_id,item\n"
            + "".join(
                f"{purchase_id},{user_id},{item}\n"
                for purchase_id, user_id, item in purchases
            )
        )
        if OUT_PATH.exists():
            OUT_PATH.unlink()

        run_script()
        assert OUT_PATH.is_file(), "The script did not generate relationships.cypher."
        challenge_lines = read_nonempty_lines(OUT_PATH)
    finally:
        USERS_PATH.write_bytes(original_users)
        PURCHASES_PATH.write_bytes(original_purchases)
        if OUT_PATH.exists():
            OUT_PATH.unlink()
        run_script()

    assert Counter(challenge_lines) == Counter(expected), (
        "The script does not derive relationships by matching purchase user_id values "
        "to user user_id values."
    )


def test_relationships_cypher_exists_and_correct():
    out_path = "/home/user/relationships.cypher"
    assert os.path.isfile(out_path), f"The output file {out_path} was not generated."

    with open(out_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 valid relationships, but found {len(lines)}. The cross join bug might not be fully fixed."

    expected_relationships = [
        "MATCH (u:User {user_id: 1}), (p:Purchase {purchase_id: 101}) CREATE (u)-[:BOUGHT]->(p);",
        "MATCH (u:User {user_id: 1}), (p:Purchase {purchase_id: 102}) CREATE (u)-[:BOUGHT]->(p);",
        "MATCH (u:User {user_id: 2}), (p:Purchase {purchase_id: 103}) CREATE (u)-[:BOUGHT]->(p);",
        "MATCH (u:User {user_id: 4}), (p:Purchase {purchase_id: 104}) CREATE (u)-[:BOUGHT]->(p);",
        "MATCH (u:User {user_id: 4}), (p:Purchase {purchase_id: 105}) CREATE (u)-[:BOUGHT]->(p);"
    ]

    for expected_relationship in expected_relationships:
        assert expected_relationship in lines, f"Missing expected relationship in output: {expected_relationship}"

    # Ensure no incorrect relationships exist (e.g. user 1 buying purchase 103)
    invalid_relationship = "MATCH (u:User {user_id: 1}), (p:Purchase {purchase_id: 103}) CREATE (u)-[:BOUGHT]->(p);"
    assert invalid_relationship not in lines, "Found an invalid relationship in the output file. The cross join bug is still present."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
