#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

USERS_CSV = "/home/user/data/users.csv"
TRANSACTIONS_CSV = "/home/user/data/transactions.csv"
SOURCE = "/home/user/analyze_graph.c"
BINARY = "/home/user/analyze_graph"
REPORT = "/home/user/centrality_report.txt"

CANONICAL_USERS = """user_id,name
1,Alice
2,Bob
3,Charlie
4,Diana
5,Eve
"""

CANONICAL_TRANSACTIONS = """tx_id,sender_id,receiver_id,amount
101,1,2,50.0
102,1,3,20.0
103,2,4,150.0
104,4,1,10.0
105,3,5,80.0
106,5,2,45.0
107,2,3,10.0
"""

CANONICAL_OUTPUT = [
    "2,Bob,255.0",
    "4,Diana,160.0",
    "5,Eve,125.0",
    "3,Charlie,110.0",
    "1,Alice,80.0",
]


def write_inputs(users, transactions):
    os.makedirs(os.path.dirname(USERS_CSV), exist_ok=True)
    with open(USERS_CSV, "w") as f:
        f.write(users)
    with open(TRANSACTIONS_CSV, "w") as f:
        f.write(transactions)


def run_and_read(executable):
    if os.path.lexists(REPORT):
        os.unlink(REPORT)
    subprocess.run([executable], check=True, timeout=10, cwd="/home/user")
    assert os.path.isfile(REPORT), f"{executable} did not create {REPORT}"
    with open(REPORT, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_csv_files_exist():
    """Check if the dataset CSV files exist and contain the correct headers/content."""
    assert os.path.isfile(USERS_CSV), f"Missing file: {USERS_CSV}"
    assert os.path.isfile(TRANSACTIONS_CSV), f"Missing file: {TRANSACTIONS_CSV}"

    with open(USERS_CSV, "r") as f:
        content = f.read().strip()
        assert "user_id,name" in content, "users.csv does not contain the correct header."
        assert "1,Alice" in content, "users.csv does not contain Alice."

    with open(TRANSACTIONS_CSV, "r") as f:
        content = f.read().strip()
        assert "tx_id,sender_id,receiver_id,amount" in content, "transactions.csv does not contain the correct header."
        assert "101,1,2,50.0" in content, "transactions.csv missing expected data."

    assert content + "\n" == CANONICAL_TRANSACTIONS, "transactions.csv does not exactly match the requested dataset."
    with open(USERS_CSV, "r") as f:
        assert f.read() == CANONICAL_USERS, "users.csv does not exactly match the requested dataset."


def test_c_program_exists():
    """Check if the C source code and compiled binary exist."""
    assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing compiled binary: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled binary {BINARY} is not an ELF executable."


def test_program_reads_and_computes_graph():
    """Execute both the submitted binary and a fresh build on verifier-generated data."""
    freshly_compiled = "/tmp/analyze_graph_from_source"
    subprocess.run(
        ["gcc", SOURCE, "-o", freshly_compiled],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # First ensure the submitted executable computes the required report.
    write_inputs(CANONICAL_USERS, CANONICAL_TRANSACTIONS)
    assert run_and_read(BINARY) == CANONICAL_OUTPUT

    token = secrets.token_hex(4)
    names = {i: f"VerifierUser{i}_{token}" for i in range(1, 6)}
    weights = [secrets.randbelow(80) + 11 for _ in range(4)]
    a, b, c, d = weights
    edges = [
        (101, 1, 3, a),
        (102, 2, 3, a),
        (103, 4, 1, b),
        (104, 4, 2, b),
        (105, 1, 5, c),
        (106, 2, 5, c),
        (107, 3, 4, d),
    ]

    users_text = "user_id,name\n" + "".join(f"{uid},{names[uid]}\n" for uid in range(1, 6))
    transactions_text = "tx_id,sender_id,receiver_id,amount\n" + "".join(
        f"{tx},{sender},{receiver},{amount}.0\n"
        for tx, sender, receiver, amount in edges
    )

    totals = {uid: 0.0 for uid in names}
    for _, sender, receiver, amount in edges:
        totals[sender] += amount
        totals[receiver] += amount
    expected = [
        f"{uid},{names[uid]},{totals[uid]:.1f}"
        for uid in sorted(names, key=lambda uid: (-totals[uid], uid))
    ]

    try:
        write_inputs(users_text, transactions_text)
        assert run_and_read(BINARY) == expected, "Submitted executable did not compute the generated graph correctly."

        write_inputs(users_text, transactions_text)
        assert run_and_read(freshly_compiled) == expected, "Freshly compiled C source did not compute the generated graph correctly."
    finally:
        # Restore the instructed final state and regenerate its report.
        write_inputs(CANONICAL_USERS, CANONICAL_TRANSACTIONS)
        if os.path.isfile(BINARY) and os.access(BINARY, os.X_OK):
            subprocess.run([BINARY], timeout=10, cwd="/home/user", check=False)


def test_centrality_report():
    """Check if the centrality report exists and contains the correct sorted output."""
    assert os.path.isfile(REPORT), f"Missing output report: {REPORT}"

    expected_output = [
        "2,Bob,255.0",
        "4,Diana,160.0",
        "5,Eve,125.0",
        "3,Charlie,110.0",
        "1,Alice,80.0"
    ]

    with open(REPORT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_output, (
        f"Report content does not match expected output.\n"
        f"Expected: {expected_output}\n"
        f"Got: {lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
