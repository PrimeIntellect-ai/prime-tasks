#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import socket
import sqlite3
import subprocess
from collections import Counter
from decimal import Decimal, InvalidOperation

import pytest

DB_PATH = "/home/user/finance.db"
CLIENTS_PATH = "/home/user/incoming/clients.json"
TRANSACTIONS_PATH = "/home/user/incoming/transactions.csv"
SIGNER_PATH = "/app/tx_signer"


def send_request(client_id, timeout=5.0):
    """Send one GET request and return the normalized response."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(("127.0.0.1", 9000))
        s.sendall(f"GET {client_id}\n".encode("utf-8"))

        response = b""
        while b"END\n" not in response.replace(b"\r\n", b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
        s.close()
        return response.decode("utf-8").replace("\r\n", "\n")
    except ConnectionRefusedError:
        pytest.fail("Connection refused. Ensure the TCP server is running on 127.0.0.1:9000.")
    except socket.timeout:
        pytest.fail("Socket timeout. The server did not respond with 'END\\n' in time.")
    except Exception as e:
        pytest.fail(f"Network error: {e}")


def response_lines(client_id):
    response = send_request(client_id)
    lines = [line for line in response.split("\n") if line.strip()]
    assert lines and lines[-1] == "END", f"Response for {client_id!r} did not end with END: {response!r}"
    assert lines.count("END") == 1, f"Response for {client_id!r} contained an invalid END marker: {response!r}"
    return lines


def load_inputs():
    with open(CLIENTS_PATH, encoding="utf-8") as f:
        clients = json.load(f)
    with open(TRANSACTIONS_PATH, newline="", encoding="utf-8") as f:
        transactions = list(csv.DictReader(f))
    return clients, transactions


def signer(tx_id, amount):
    result = subprocess.run(
        [SIGNER_PATH, tx_id, amount],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    signature = result.stdout.strip()
    assert re.fullmatch(r"[0-9a-fA-F]+", signature), f"Signer returned an invalid signature: {signature!r}"
    return signature


def expected_for(client_id):
    clients, transactions = load_inputs()
    statuses = {str(row["client_id"]): str(row["status"]) for row in clients}
    if statuses.get(client_id) != "active":
        return ["END"]
    lines = []
    for row in transactions:
        if row["client_id"] == client_id:
            lines.append(f'{row["tx_id"]},{row["amount"]},{signer(row["tx_id"], row["amount"])}')
    lines.append("END")
    return lines


def quote_identifier(name):
    return '"' + name.replace('"', '""') + '"'


def decimal_value(value):
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def relation_rows(conn):
    names = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'"
        )
    ]
    relations = []
    for name in names:
        cursor = conn.execute(f"SELECT * FROM {quote_identifier(name)}")
        columns = [item[0] for item in cursor.description]
        relations.append((name, columns, cursor.fetchall()))
    return relations


def test_finance_database_contains_bulk_imported_inputs():
    assert os.path.isfile(DB_PATH), f"Required SQLite database does not exist: {DB_PATH}"
    with open(DB_PATH, "rb") as f:
        assert f.read(16) == b"SQLite format 3\x00", f"{DB_PATH} is not a SQLite database"

    clients, transactions = load_inputs()
    expected_clients = Counter((str(r["client_id"]), str(r["status"])) for r in clients)
    expected_transactions = Counter(
        (str(r["tx_id"]), str(r["client_id"]), Decimal(str(r["amount"])))
        for r in transactions
    )

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        relations = relation_rows(conn)
        found_clients = False
        found_transactions = False

        for _name, columns, rows in relations:
            lowered = {column.lower(): index for index, column in enumerate(columns)}
            if {"client_id", "status"}.issubset(lowered):
                actual = Counter(
                    (str(row[lowered["client_id"]]), str(row[lowered["status"]]))
                    for row in rows
                )
                if actual == expected_clients:
                    found_clients = True

            if {"tx_id", "client_id", "amount"}.issubset(lowered):
                converted = []
                valid = True
                for row in rows:
                    amount = decimal_value(row[lowered["amount"]])
                    if amount is None:
                        valid = False
                        break
                    converted.append(
                        (
                            str(row[lowered["tx_id"]]),
                            str(row[lowered["client_id"]]),
                            amount,
                        )
                    )
                if valid and Counter(converted) == expected_transactions:
                    found_transactions = True

        assert found_clients, "No database table or view contains the complete imported clients.json data"
        assert found_transactions, "No database table or view contains the complete imported transactions.csv data"
    finally:
        conn.close()


def test_server_active_client_c001():
    """Test that the server returns correct transactions for active client C001."""
    response = send_request("C001")
    expected_lines = [
        "TX1001,150.50,227fa2fcddf6a",
        "TX1002,200.00,227fa32ab89fb",
        "END"
    ]

    actual_lines = [line for line in response.split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Expected output for C001 to be {expected_lines}, but got {actual_lines}"


def test_server_suspended_client_c002():
    """Test that the server returns only END for suspended client C002."""
    response = send_request("C002")
    actual_lines = [line for line in response.split('\n') if line.strip()]

    assert actual_lines == ["END"], f"Expected output for suspended client C002 to be ['END'], but got {actual_lines}"


def test_server_active_client_c003():
    """Test that the server returns correct transactions for active client C003."""
    response = send_request("C003")
    expected_lines = [
        "TX1004,500.00,227fa3d666299",
        "TX1005,10.00,9f30327f31c7",
        "END"
    ]

    actual_lines = [line for line in response.split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Expected output for C003 to be {expected_lines}, but got {actual_lines}"


def test_server_nonexistent_client():
    """Test that the server returns only END for a client that does not exist."""
    response = send_request("NONEXISTENT")
    actual_lines = [line for line in response.split('\n') if line.strip()]

    assert actual_lines == ["END"], f"Expected output for nonexistent client to be ['END'], but got {actual_lines}"


def test_all_input_clients_against_join_and_real_signer():
    clients, _transactions = load_inputs()
    for client in clients:
        client_id = str(client["client_id"])
        assert response_lines(client_id) == expected_for(client_id)


def test_unpredictable_nonexistent_clients_and_sequential_requests():
    clients, _transactions = load_inputs()
    existing = {str(row["client_id"]) for row in clients}
    unknown = []
    while len(unknown) < 3:
        candidate = "UNKNOWN_" + secrets.token_hex(12)
        if candidate not in existing:
            unknown.append(candidate)

    for client_id in unknown:
        assert response_lines(client_id) == ["END"]

    active = [str(row["client_id"]) for row in clients if row["status"] == "active"]
    for client_id in active:
        assert response_lines(client_id) == expected_for(client_id)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
