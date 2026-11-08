#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

GO_FILE_PATH = "/home/user/etl_extract.go"
OUTPUT_FILE_PATH = "/home/user/summary.jsonl"
DB_FILE_PATH = "/home/user/warehouse.db"
GO_MOD_PATH = "/home/user/go.mod"


def read_records(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, found {len(lines)}."
    records = []
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} is not valid JSON: {line}")
        assert isinstance(record, dict), f"Line {i + 1} must be a JSON object."
        assert set(record.keys()) == {"category", "total_amount"}, (
            f"Line {i + 1} must have exactly the keys 'category' and 'total_amount'."
        )
        assert isinstance(record["category"], str), "'category' must be a string."
        assert isinstance(record["total_amount"], (int, float)) and not isinstance(record["total_amount"], bool), (
            "'total_amount' must be numeric."
        )
        records.append(record)
    return records


def records_by_category(records):
    result = {}
    for record in records:
        category = record["category"]
        assert category not in result, f"Duplicate category '{category}' in output."
        result[category] = float(record["total_amount"])
    return result


def strip_go_comments(source):
    out = []
    i = 0
    state = "code"
    while i < len(source):
        c = source[i]
        n = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if c == '/' and n == '/':
                state = "line_comment"
                out.extend("  ")
                i += 2
            elif c == '/' and n == '*':
                state = "block_comment"
                out.extend("  ")
                i += 2
            elif c == '"':
                state = "quoted"
                out.append(c)
                i += 1
            elif c == '`':
                state = "raw"
                out.append(c)
                i += 1
            else:
                out.append(c)
                i += 1
        elif state == "line_comment":
            if c == '\n':
                state = "code"
                out.append(c)
            else:
                out.append(' ')
            i += 1
        elif state == "block_comment":
            if c == '*' and n == '/':
                state = "code"
                out.extend("  ")
                i += 2
            else:
                out.append('\n' if c == '\n' else ' ')
                i += 1
        elif state == "quoted":
            out.append(c)
            i += 1
            if c == '\\' and i < len(source):
                out.append(source[i])
                i += 1
            elif c == '"':
                state = "code"
        else:
            out.append(c)
            i += 1
            if c == '`':
                state = "code"
    return ''.join(out)


def split_go_arguments(text):
    args, start, depth, i, state = [], 0, 0, 0, "code"
    while i < len(text):
        c = text[i]
        if state == "code":
            if c == '"':
                state = "quoted"
            elif c == '`':
                state = "raw"
            elif c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            elif c == ',' and depth == 0:
                args.append(text[start:i].strip())
                start = i + 1
        elif state == "quoted":
            if c == '\\':
                i += 1
            elif c == '"':
                state = "code"
        elif state == "raw" and c == '`':
            state = "code"
        i += 1
    args.append(text[start:].strip())
    return args


def find_query_calls(source):
    calls = []
    pattern = re.compile(r"\.\s*(QueryContext|QueryRowContext|QueryRow|Query)\s*\(")
    for match in pattern.finditer(source):
        start = match.end()
        i, depth, state = start, 1, "code"
        while i < len(source) and depth:
            c = source[i]
            if state == "code":
                if c == '"':
                    state = "quoted"
                elif c == '`':
                    state = "raw"
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
            elif state == "quoted":
                if c == '\\':
                    i += 1
                elif c == '"':
                    state = "code"
            elif state == "raw" and c == '`':
                state = "code"
            i += 1
        assert depth == 0, "Could not parse the database query call."
        calls.append((match.group(1), source[start:i - 1], match.start()))
    return calls


def go_strings(expression):
    parts = []
    for match in re.finditer(r'`([^`]*)`|"((?:\\.|[^"\\])*)"', expression, re.S):
        if match.group(1) is not None:
            parts.append(match.group(1))
        else:
            try:
                parts.append(json.loads('"' + match.group(2) + '"'))
            except json.JSONDecodeError:
                parts.append(match.group(2))
    return ''.join(parts)


def resolve_query_sql(source, expression, call_position):
    direct = go_strings(expression)
    if direct:
        return direct
    identifier = expression.strip()
    assert re.fullmatch(r"[A-Za-z_]\w*", identifier), "The SQL passed to the query call could not be inspected."
    prefix = source[:call_position]
    assignment = re.compile(
        r"(?:\bconst\s+|\bvar\s+)?" + re.escape(identifier) +
        r"(?:\s+string)?\s*(?::=|=)\s*(.*?)(?=\n\s*(?:[A-Za-z_]\w*\s*(?::=|=)|if\b|for\b|return\b)|;)",
        re.S,
    )
    matches = list(assignment.finditer(prefix + ";"))
    assert matches, f"Could not find the SQL assigned to {identifier}."
    sql = go_strings(matches[-1].group(1))
    assert sql, f"Could not parse the SQL assigned to {identifier}."
    return sql


def test_go_file_exists():
    assert os.path.exists(GO_FILE_PATH), f"Go source file {GO_FILE_PATH} is missing."
    assert os.path.isfile(GO_FILE_PATH), f"{GO_FILE_PATH} is not a file."


def test_go_implementation_requirements():
    with open(GO_FILE_PATH, "r", encoding="utf-8") as f:
        raw_source = f.read()
    source = strip_go_comments(raw_source)

    assert re.search(r'["`]database/sql["`]', source), "The program must import database/sql."
    assert re.search(r'["`]github\.com/mattn/go-sqlite3["`]', source), (
        "The program must import github.com/mattn/go-sqlite3."
    )
    assert re.search(r"\bsql\s*\.\s*Open\s*\(", source), "The program must open SQLite through database/sql."

    calls = find_query_calls(source)
    assert len(calls) == 1, f"Expected exactly one database query call, found {len(calls)}."
    method, argument_text, call_position = calls[0]
    args = split_go_arguments(argument_text)
    sql_index = 1 if "Context" in method else 0
    assert len(args) > sql_index, "The database query call has no SQL argument."
    query_sql = resolve_query_sql(source, args[sql_index], call_position)

    cte = re.search(
        r"\bWITH\b[\s\S]*?\bAS\s*\(\s*SELECT\b[\s\S]*?\bFROM\s+[^\s,()]*SYS_DIM_A[^\s,()]*[\s\S]*?\bSTATUS\b[\s\S]*?\)",
        query_sql,
        re.I,
    )
    subquery = re.search(
        r"(?:\bFROM\b|\bJOIN\b)\s*\(\s*SELECT\b[\s\S]*?\bFROM\s+[^\s,()]*SYS_DIM_A[^\s,()]*[\s\S]*?\bSTATUS\b[\s\S]*?\)",
        query_sql,
        re.I,
    )
    assert cte or subquery, "The executed query must use a CTE or subquery that filters sys_dim_a by status."

    assert os.path.isfile(GO_MOD_PATH), "/home/user/go.mod is missing."
    with open(GO_MOD_PATH, "r", encoding="utf-8") as f:
        go_mod = f.read()
    assert re.search(r"(?m)^module\s+etl\s*$", go_mod), "go.mod must declare module etl."
    assert "github.com/mattn/go-sqlite3" in go_mod, "go.mod must require github.com/mattn/go-sqlite3."


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE_PATH), f"Output file {OUTPUT_FILE_PATH} is missing."
    assert os.path.isfile(OUTPUT_FILE_PATH), f"{OUTPUT_FILE_PATH} is not a file."


def test_output_file_contents():
    actual_records = records_by_category(read_records(OUTPUT_FILE_PATH))
    expected_records = {"Books": 20.0, "Electronics": 200.0}
    assert len(actual_records) == 2, "Expected exactly 2 distinct categories in the output."
    for category, expected_amount in expected_records.items():
        assert category in actual_records, f"Category '{category}' is missing from the output."
        assert actual_records[category] == expected_amount, (
            f"Expected total_amount for '{category}' to be {expected_amount}, "
            f"but got {actual_records[category]}."
        )


def test_program_executes_against_database_and_regenerates_output():
    token = secrets.token_hex(6)
    category_one = "DynamicA_" + token
    category_two = "DynamicB_" + token
    cents_one = secrets.randbelow(7000) + 1000
    cents_two = secrets.randbelow(7000) + 1000
    cents_three = secrets.randbelow(7000) + 1000
    expected = {
        category_one: (cents_one + cents_two) / 100.0,
        category_two: cents_three / 100.0,
    }

    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, "warehouse.db")
        output_backup = os.path.join(backup_dir, "summary.jsonl")
        shutil.copy2(DB_FILE_PATH, db_backup)
        shutil.copy2(OUTPUT_FILE_PATH, output_backup)
        try:
            os.remove(DB_FILE_PATH)
            conn = sqlite3.connect(DB_FILE_PATH)
            conn.executescript("""
                CREATE TABLE sys_dim_a (
                    a_id INTEGER PRIMARY KEY,
                    category_name TEXT,
                    status TEXT
                );
                CREATE TABLE sys_dim_b (
                    b_id INTEGER PRIMARY KEY,
                    region_code TEXT
                );
                CREATE TABLE sys_trx_01 (
                    t_id INTEGER PRIMARY KEY,
                    dim_a_id INTEGER,
                    dim_b_id INTEGER,
                    amount REAL,
                    ts DATETIME,
                    FOREIGN KEY(dim_a_id) REFERENCES sys_dim_a(a_id),
                    FOREIGN KEY(dim_b_id) REFERENCES sys_dim_b(b_id)
                );
            """)
            conn.executemany(
                "INSERT INTO sys_dim_a(a_id, category_name, status) VALUES (?, ?, ?)",
                [(101, category_one, "active"), (202, category_two, "active"),
                 (303, "Inactive_" + token, "inactive")],
            )
            conn.executemany(
                "INSERT INTO sys_dim_b(b_id, region_code) VALUES (?, ?)",
                [(11, "East"), (22, "West")],
            )
            rows = [
                (101, 11, cents_one / 100.0, "2023-03-04 05:06:07"),
                (101, 11, cents_two / 100.0, "2025-01-02 03:04:05"),
                (202, 11, cents_three / 100.0, "2024-08-09 10:11:12"),
                (101, 11, 9001.23, "2023-01-01 00:00:00"),
                (202, 11, 8002.34, "2022-12-31 23:59:59"),
                (101, 22, 7003.45, "2024-02-03 04:05:06"),
                (303, 11, 6004.56, "2024-02-03 04:05:06"),
            ]
            conn.executemany(
                "INSERT INTO sys_trx_01(dim_a_id, dim_b_id, amount, ts) VALUES (?, ?, ?, ?)", rows
            )
            conn.commit()
            conn.close()

            os.chmod(DB_FILE_PATH, 0o777)
            if os.path.exists(OUTPUT_FILE_PATH):
                os.remove(OUTPUT_FILE_PATH)

            result = subprocess.run(
                ["go", "run", GO_FILE_PATH],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=90,
            )
            assert result.returncode == 0, (
                f"The Go program failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(OUTPUT_FILE_PATH), "The executed Go program did not create summary.jsonl."
            actual = records_by_category(read_records(OUTPUT_FILE_PATH))
            assert set(actual) == set(expected), "The regenerated output has incorrect categories."
            for category, amount in expected.items():
                assert math.isclose(actual[category], amount, rel_tol=0, abs_tol=0.005), (
                    f"Incorrect dynamic total for {category}: expected {amount}, got {actual[category]}."
                )
        finally:
            if os.path.exists(DB_FILE_PATH):
                os.remove(DB_FILE_PATH)
            shutil.copy2(db_backup, DB_FILE_PATH)
            if os.path.exists(OUTPUT_FILE_PATH):
                os.remove(OUTPUT_FILE_PATH)
            shutil.copy2(output_backup, OUTPUT_FILE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
