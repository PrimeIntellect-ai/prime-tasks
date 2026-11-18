#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import csv
import uuid
import sqlite3
import subprocess
from collections import Counter
import pytest

HOME = "/home/user"
NT_PATH = f"{HOME}/graph.nt"
GO_PATH = f"{HOME}/etl.go"
DB_PATH = f"{HOME}/graph.db"
CSV_PATH = f"{HOME}/result.csv"
QUERY_PATH = f"{HOME}/query.rq"


def parse_nt(path):
    triples = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            assert len(parts) >= 4 and parts[-1] == ".", f"Malformed N-Triples line: {line}"
            triples.append((parts[0], parts[1], parts[2]))
    return triples


def expected_pairs(triples):
    follows_target = {s for s, p, o in triples if p == "<follows>" and o == "<http://example.org/TargetUser>"}
    pairs = [
        (s.strip("<>"), o.strip("<>"))
        for s, p, o in triples
        if p == "<knows>" and s in follows_target and o in follows_target
    ]
    pairs.sort()
    return pairs


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def remove_outputs():
    for path in (DB_PATH, CSV_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_etl():
    cmd = [
        "timeout", "120s", "runuser", "-u", "user", "--",
        "env", "HOME=/home/user", "GOCACHE=/home/user/.cache/go-build",
        "GOMODCACHE=/home/user/go/pkg/mod",
        "bash", "-c", "cd /home/user && go run etl.go",
    ]
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def assert_db_exact(expected):
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT subject, predicate, object FROM triples").fetchall()
    finally:
        conn.close()
    assert Counter(rows) == Counter(expected), "The triples table does not exactly contain the input N-Triples data."


def assert_csv_exact(expected):
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} is missing."
    rows = read_csv(CSV_PATH)
    assert rows, "CSV file is empty."
    assert rows[0] == ["user1", "user2"], f"Expected CSV header ['user1', 'user2'], got {rows[0]}"
    assert all(len(row) == 2 for row in rows[1:]), "CSV data rows must have exactly two columns."
    assert [(row[0], row[1]) for row in rows[1:]] == expected


def strip_sparql_comments(text):
    result = []
    in_iri = False
    in_string = None
    i = 0
    while i < len(text):
        ch = text[i]
        if in_string:
            result.append(ch)
            if ch == "\\" and i + 1 < len(text):
                i += 1
                result.append(text[i])
            elif ch == in_string:
                in_string = None
        elif ch in ('\"', "'"):
            in_string = ch
            result.append(ch)
        elif ch == "<":
            in_iri = True
            result.append(ch)
        elif ch == ">" and in_iri:
            in_iri = False
            result.append(ch)
        elif ch == "#" and not in_iri:
            while i < len(text) and text[i] not in "\r\n":
                i += 1
            if i < len(text):
                result.append(text[i])
        else:
            result.append(ch)
        i += 1
    return "".join(result)


def parse_basic_graph_patterns(body):
    token_re = re.compile(r"<[^>]*>|[?$][A-Za-z_][A-Za-z0-9_]*|[.;,]")
    tokens = token_re.findall(body)
    residue = token_re.sub(" ", body)
    assert not residue.strip(), f"Unsupported or invalid content in SPARQL WHERE clause: {residue.strip()}"

    def term(tok):
        return tok.startswith("<") or tok.startswith("?") or tok.startswith("$")

    patterns = []
    i = 0
    subject = predicate = None
    need_new_subject = True
    while i < len(tokens):
        if need_new_subject:
            assert i + 2 < len(tokens), "Incomplete triple pattern in SPARQL query."
            subject, predicate, obj = tokens[i:i+3]
            assert term(subject) and term(predicate) and term(obj), "Invalid SPARQL triple pattern."
            patterns.append((subject, predicate, obj))
            i += 3
            need_new_subject = False
        if i >= len(tokens):
            break
        sep = tokens[i]
        i += 1
        assert sep in (".", ";", ","), "Invalid SPARQL triple separator."
        if sep == ".":
            need_new_subject = True
        elif sep == ";":
            if i < len(tokens) and tokens[i] == ".":
                i += 1
                need_new_subject = True
                continue
            assert i + 1 < len(tokens), "Incomplete SPARQL property list."
            predicate, obj = tokens[i:i+2]
            assert term(predicate) and term(obj), "Invalid SPARQL property list."
            patterns.append((subject, predicate, obj))
            i += 2
        else:
            assert i < len(tokens) and term(tokens[i]), "Incomplete SPARQL object list."
            obj = tokens[i]
            i += 1
            patterns.append((subject, predicate, obj))
    assert not need_new_subject or i == len(tokens)
    return patterns


def validate_query_semantics(content):
    text = strip_sparql_comments(content).strip()
    # BASE/PREFIX declarations are syntactically allowed, although the required
    # graph terms below must still appear as the explicit IRIs from the task.
    declarations = re.compile(r"(?is)^\s*(?:(?:BASE\s+<[^>]+>|PREFIX\s+[A-Za-z][\w-]*:\s*<[^>]*>)\s*)*")
    text = text[declarations.match(text).end():]
    match = re.match(r"(?is)^SELECT\s+(DISTINCT\s+|REDUCED\s+)?(.*?)\s+(?:WHERE\s*)?\{", text)
    assert match, "query.rq is not a valid SELECT query with a WHERE group."
    projection = re.findall(r"[?$][A-Za-z_][A-Za-z0-9_]*", match.group(2))
    assert set(projection) == {"?x", "?y"} and len(projection) == 2, "SPARQL query must project exactly ?x and ?y."

    open_pos = match.end() - 1
    depth = 0
    close_pos = None
    for i in range(open_pos, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                close_pos = i
                break
            assert depth >= 0, "Unbalanced braces in SPARQL query."
    assert close_pos is not None, "Unbalanced braces in SPARQL query."
    trailing = text[close_pos + 1:].strip()
    if trailing:
        assert re.fullmatch(r"(?is)ORDER\s+BY\s+(?:ASC\s*\(\s*)?[?$]x\s*\)?(?:\s+(?:ASC\s*\(\s*)?[?$]y\s*\)?)?", trailing), "Unexpected solution modifier after the WHERE clause."

    patterns = parse_basic_graph_patterns(text[open_pos + 1:close_pos])
    normalized = [(s.replace("$", "?", 1), p, o.replace("$", "?", 1)) for s, p, o in patterns]
    required = Counter([
        ("?x", "<follows>", "<http://example.org/TargetUser>"),
        ("?y", "<follows>", "<http://example.org/TargetUser>"),
        ("?x", "<knows>", "?y"),
    ])
    assert Counter(normalized) == required, "SPARQL WHERE clause must be exactly the three required conjunctive triple patterns."


def test_00_execute_go_pipeline_on_derived_input():
    assert os.path.isfile(GO_PATH), f"Go ETL source {GO_PATH} is missing or is not a regular file."
    original = open(NT_PATH, "rb").read()
    marker = uuid.uuid4().hex
    base = f"http://verification.invalid/{marker}"
    hidden_triples = [
        (f"<{base}/alice>", "<follows>", "<http://example.org/TargetUser>"),
        (f"<{base}/bob>", "<follows>", "<http://example.org/TargetUser>"),
        (f"<{base}/carol>", "<follows>", "<http://example.org/TargetUser>"),
        (f"<{base}/alice>", "<knows>", f"<{base}/bob>"),
        (f"<{base}/carol>", "<knows>", f"<{base}/alice>"),
        (f"<{base}/bob>", "<knows>", f"<{base}/outsider>"),
        (f"<{base}/noise>", "<follows>", f"<{base}/alice>"),
    ]
    hidden_error = None
    original_run = None
    try:
        with open(NT_PATH, "w") as f:
            for s, p, o in hidden_triples:
                f.write(f"{s} {p} {o} .\n")
        remove_outputs()
        proc = run_etl()
        assert proc.returncode == 0, f"Go ETL failed on a derived input (exit {proc.returncode}):\n{proc.stdout}"
        assert_db_exact(hidden_triples)
        assert_csv_exact(expected_pairs(hidden_triples))
    except BaseException as exc:
        hidden_error = exc
    finally:
        with open(NT_PATH, "wb") as f:
            f.write(original)
        remove_outputs()
        original_run = run_etl()

    if hidden_error is not None:
        raise hidden_error
    assert original_run.returncode == 0, f"Go ETL failed on graph.nt (exit {original_run.returncode}):\n{original_run.stdout}"


def test_query_rq():
    """Test that the SPARQL query file exists, contains required terms, and has the required semantics."""
    file_path = QUERY_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()
    assert "?x" in content, "Query missing variable ?x"
    assert "?y" in content, "Query missing variable ?y"
    assert "<follows>" in content, "Query missing <follows> relation"
    assert "<knows>" in content, "Query missing <knows> relation"
    assert "<http://example.org/TargetUser>" in content, "Query missing TargetUser URI"
    validate_query_semantics(content)


def test_sqlite_db_and_indexes():
    """Test that the SQLite database exists, has the right schema, exact data, and useful indexes."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='triples'")
        assert cursor.fetchone() is not None, "Table 'triples' is missing in the database."

        cursor.execute("PRAGMA table_info(triples)")
        columns = [row[1] for row in cursor.fetchall()]
        assert set(columns).issuperset({"subject", "predicate", "object"}), "Table 'triples' missing required columns."

        nt_triples = parse_nt(NT_PATH)
        cursor.execute("SELECT count(*) FROM triples")
        db_count = cursor.fetchone()[0]
        assert db_count == len(nt_triples), f"Expected {len(nt_triples)} rows in triples table, found {db_count}."
        cursor.execute("SELECT subject, predicate, object FROM triples")
        assert Counter(cursor.fetchall()) == Counter(nt_triples), "Database triple values do not exactly match graph.nt."

        cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='triples' AND name NOT LIKE 'sqlite_autoindex%'")
        indexes = cursor.fetchall()
        assert len(indexes) > 0, "No custom indexes found on the 'triples' table to optimize the query."

        useful = False
        for name, sql in indexes:
            escaped = name.replace("'", "''")
            info = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
            indexed_columns = [row[2].lower() for row in info if row[2] is not None]
            sql_lower = (sql or "").lower()
            if (len(indexed_columns) >= 2 and indexed_columns[0] == "predicate" and
                    ("subject" in indexed_columns[1:] or "object" in indexed_columns[1:])):
                useful = True
            if (" where " in sql_lower and "predicate" in sql_lower and indexed_columns and
                    indexed_columns[0] in ("subject", "object")):
                useful = True
        assert useful, "Custom indexes do not support predicate plus subject/object lookups needed by the graph query."

        plan = cursor.execute("""
            EXPLAIN QUERY PLAN
            SELECT k.subject, k.object
            FROM triples AS k
            JOIN triples AS fx ON fx.subject = k.subject
            JOIN triples AS fy ON fy.subject = k.object
            WHERE k.predicate = '<knows>'
              AND fx.predicate = '<follows>'
              AND fx.object = '<http://example.org/TargetUser>'
              AND fy.predicate = '<follows>'
              AND fy.object = '<http://example.org/TargetUser>'
        """).fetchall()
        assert any("INDEX" in row[3].upper() for row in plan), "SQLite does not use an index for the equivalent graph query."
    finally:
        conn.close()


def test_result_csv():
    """Test that the result CSV exists, has the correct header, and exact expected data."""
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} is missing."
    assert os.path.exists(NT_PATH), f"Original graph file {NT_PATH} is missing."
    triples = parse_nt(NT_PATH)
    expected = expected_pairs(triples)
    reader = read_csv(CSV_PATH)
    assert len(reader) > 0, "CSV file is empty."
    assert reader[0] == ["user1", "user2"], f"Expected CSV header ['user1', 'user2'], got {reader[0]}"
    assert all(len(row) == 2 for row in reader[1:]), "CSV data rows must have exactly two columns."
    actual_pairs = [(row[0], row[1]) for row in reader[1:]]
    assert actual_pairs == expected, f"CSV content does not match expected result. Expected {len(expected)} pairs, got {len(actual_pairs)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
