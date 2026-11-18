#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import socket
import sqlite3
import pytest

DB_PATH = "/app/graph_data.db"
TOKEN = secrets.token_hex(12)
OWNER = f"VerifierResearcher_{TOKEN}"
CONTACT_1 = f"VerifierContactA_{TOKEN}"
CONTACT_2 = f"VerifierContactB_{TOKEN}"
CONCEPTS = [
    f"Verifier Concept Alpha {TOKEN}",
    f"Verifier Concept Delta {TOKEN}",
    f"Verifier Concept Omega {TOKEN}",
]


def send_query(name: str) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        try:
            s.connect(('127.0.0.1', 8080))
        except ConnectionRefusedError:
            pytest.fail("TCP server is not listening on 127.0.0.1:8080. Did you start the server?")

        s.sendall(f"{name}\n".encode('utf-8'))
        response = b""
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                pytest.fail("Server timed out while waiting for a response.")
            if not chunk:
                break
            response += chunk
            if b'\n' in chunk:
                break
        return response.decode('utf-8')


def expected_response(name: str) -> str:
    with sqlite3.connect(DB_PATH, timeout=10) as db:
        rows = db.execute(
            """
            SELECT DISTINCT c.concept_name
            FROM t1 AS researcher
            JOIN t2 AS knows ON knows.src_id = researcher.id
            JOIN t3 AS likes ON likes.src_id = knows.dst_id
            JOIN t4 AS c ON c.id = likes.dst_id
            WHERE researcher.name = ?
            ORDER BY c.concept_name
            """,
            (name,),
        ).fetchall()
    return ",".join(row[0] for row in rows) + "\n"


def seed_random_graph():
    with sqlite3.connect(DB_PATH, timeout=10) as db:
        next_researcher = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM t1").fetchone()[0]
        owner_id = next_researcher
        contact_1_id = next_researcher + 1
        contact_2_id = next_researcher + 2
        next_concept = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM t4").fetchone()[0]

        db.executemany(
            "INSERT INTO t1(id, name) VALUES (?, ?)",
            [(owner_id, OWNER), (contact_1_id, CONTACT_1), (contact_2_id, CONTACT_2)],
        )
        db.executemany(
            "INSERT INTO t4(id, concept_name) VALUES (?, ?)",
            [(next_concept + i, concept) for i, concept in enumerate(CONCEPTS)],
        )
        db.executemany(
            "INSERT INTO t2(src_id, dst_id) VALUES (?, ?)",
            [(owner_id, contact_1_id), (owner_id, contact_2_id)],
        )
        db.executemany(
            "INSERT INTO t3(src_id, dst_id) VALUES (?, ?)",
            [
                (contact_1_id, next_concept + 2),
                (contact_1_id, next_concept),
                (contact_2_id, next_concept + 1),
            ],
        )
        db.commit()
        return contact_2_id


def test_alice_query():
    response = send_query("Alice")
    expected = "Databases,Graph Theory,Machine Learning\n"
    assert response == expected, f"Expected {repr(expected)}, but got {repr(response)}"


def test_unknown_user_query():
    response = send_query("UnknownUser")
    # Should be empty or just a newline since UnknownUser knows nobody
    assert response in ("", "\n"), f"Expected empty response or newline for unknown user, but got {repr(response)}"


def test_randomized_database_queries_and_live_update():
    contact_2_id = seed_random_graph()

    expected = expected_response(OWNER)
    response = send_query(OWNER)
    assert response == expected, f"Expected {repr(expected)}, but got {repr(response)}"

    # Change the graph after the server is already running. A real querying
    # service must observe the new database state on the next request.
    extra_concept = f"Verifier Concept Beta {TOKEN}"
    with sqlite3.connect(DB_PATH, timeout=10) as db:
        concept_id = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM t4").fetchone()[0]
        db.execute("INSERT INTO t4(id, concept_name) VALUES (?, ?)", (concept_id, extra_concept))
        db.execute("INSERT INTO t3(src_id, dst_id) VALUES (?, ?)", (contact_2_id, concept_id))
        db.commit()

    updated_expected = expected_response(OWNER)
    updated_response = send_query(OWNER)
    assert updated_response == updated_expected, (
        f"After updating the database, expected {repr(updated_expected)}, "
        f"but got {repr(updated_response)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
