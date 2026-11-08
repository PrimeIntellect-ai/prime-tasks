#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import string
import subprocess

DB_PATH = "/app/trading.db"
SOURCE_PATH = "/home/user/auditor.c"
AGENT_PATH = "/home/user/auditor"
REBUILT_PATH = "/tmp/auditor_rebuilt"


def run_auditor(path, value):
    result = subprocess.run(
        [path, value], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} failed on input {value!r} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    return result.stdout


def expected_output(conn, value):
    symbols = sorted(value.split(","))
    objects = []
    for symbol in symbols:
        row = conn.execute(
            "SELECT AVG(price) FROM "
            "(SELECT price FROM trades NOT INDEXED "
            "WHERE symbol = ? ORDER BY timestamp DESC LIMIT 3)",
            (symbol,),
        ).fetchone()
        score = 0.0 if row[0] is None else float(row[0])
        objects.append(
            '{"symbol":"%s","risk_score":%.2f}' % (symbol, score)
        )
    return "[" + ",".join(objects) + "]"


def test_dynamic_database_equivalence():
    assert os.path.isfile(SOURCE_PATH), f"Agent source not found at {SOURCE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable at {AGENT_PATH}"

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as source_file:
        source = source_file.read()

    # Ignore comments when checking that the required full-table-scan clause is
    # present in the submitted implementation.
    uncommented = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)
    assert re.search(r"FROM\s+trades\s+NOT\s+INDEXED", uncommented, re.I), (
        "auditor.c does not query trades using the required NOT INDEXED clause"
    )
    for api in ("sqlite3_open", "sqlite3_prepare", "sqlite3_bind_text", "sqlite3_step"):
        assert api in uncommented, f"auditor.c does not use the required SQLite API function {api}"

    build = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", REBUILT_PATH, "-lsqlite3"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"auditor.c failed to compile: {build.stderr}"

    backup = "/tmp/trading.db.verifier-backup"
    shutil.copy2(DB_PATH, backup)
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        rng = secrets.SystemRandom()
        alphabet = string.ascii_uppercase
        existing = {row[0] for row in conn.execute("SELECT DISTINCT symbol FROM trades")}
        hidden = []
        while len(hidden) < 24:
            symbol = "Q" + "".join(rng.choice(alphabet) for _ in range(7))
            if symbol not in existing and symbol not in hidden:
                hidden.append(symbol)

        for symbol_index, symbol in enumerate(hidden):
            trade_count = rng.randint(1, 7)
            for trade_index in range(trade_count):
                price = float(rng.randint(100, 500000))
                timestamp = f"2040-01-{symbol_index + 1:02d} 12:{trade_index:02d}:00"
                conn.execute(
                    "INSERT INTO trades(symbol, price, volume, timestamp) VALUES (?, ?, ?, ?)",
                    (symbol, price, rng.randint(1, 5000), timestamp),
                )
        conn.commit()

        nonexistent = []
        while len(nonexistent) < 12:
            symbol = "X" + "".join(rng.choice(alphabet) for _ in range(7))
            if symbol not in existing and symbol not in hidden and symbol not in nonexistent:
                nonexistent.append(symbol)

        populated = ["AAPL", "GOOG", "MSFT"] + hidden
        pool = populated + nonexistent
        cases = [
            "AAPL,GOOG,MSFT",
            ",".join(hidden[:6]),
            f"{hidden[0]},AAPL,{hidden[1]},MSFT,GOOG",
        ]
        while len(cases) < 100:
            count = rng.randint(1, 10)
            cases.append(",".join(rng.choice(pool) for _ in range(count)))

        for iteration, fuzz_input in enumerate(cases, 1):
            expected = expected_output(conn, fuzz_input)
            for executable in (AGENT_PATH, REBUILT_PATH):
                actual = run_auditor(executable, fuzz_input)
                assert actual == expected, (
                    f"Output mismatch for {executable} on iteration {iteration} "
                    f"with input {fuzz_input!r}.\nExpected:\n{expected}\nGot:\n{actual}"
                )
    finally:
        if conn is not None:
            conn.close()
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
