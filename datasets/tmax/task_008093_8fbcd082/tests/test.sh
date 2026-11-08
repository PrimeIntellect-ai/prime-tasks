#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = "/home/user/research_data.db"
SOURCE_PATH = "/home/user/metrics.cpp"
BINARY_PATH = "/home/user/metrics"
JSON_PATH = "/home/user/metrics_output.json"
CYPHER_PATH = "/home/user/graph_setup.cypher"


def compute_expected_metrics():
    """Computes the expected metrics directly from the SQLite database."""
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    WITH AuthorCitations AS (
        SELECT
            a.id AS author_id,
            a.name AS author_name,
            i.name AS institution_name,
            COUNT(c.cited_paper_id) AS total_citations
        FROM authors a
        JOIN institutions i ON a.institution_id = i.id
        LEFT JOIN authorships ash ON a.id = ash.author_id
        LEFT JOIN citations c ON ash.paper_id = c.cited_paper_id
        GROUP BY a.id, a.name, i.name
    )
    SELECT
        author_id,
        author_name,
        institution_name,
        total_citations,
        RANK() OVER (PARTITION BY institution_name ORDER BY total_citations DESC) AS institution_rank
    FROM AuthorCitations
    ORDER BY total_citations DESC, author_id ASC;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [
        {
            "author_id": row[0],
            "author_name": row[1],
            "institution_name": row[2],
            "total_citations": row[3],
            "institution_rank": row[4],
        }
        for row in rows
    ]


def load_actual_json():
    assert os.path.exists(JSON_PATH), f"JSON output file missing at {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")


def assert_json_matches(actual_json, expected_json):
    assert isinstance(actual_json, list), "JSON output must be a list of objects."
    assert len(actual_json) == len(expected_json), f"Expected {len(expected_json)} authors in JSON, found {len(actual_json)}."

    required_keys = {
        "author_id", "author_name", "institution_name",
        "total_citations", "institution_rank"
    }
    for i, (actual, expected) in enumerate(zip(actual_json, expected_json)):
        assert isinstance(actual, dict), f"Entry {i} must be a JSON object."
        assert set(actual) == required_keys, f"Entry {i} has an incorrect JSON schema."
        assert actual.get("author_id") == expected["author_id"], f"Mismatch at index {i}: expected author_id {expected['author_id']}, got {actual.get('author_id')}"
        assert actual.get("author_name") == expected["author_name"], f"Mismatch at index {i}: expected author_name {expected['author_name']}, got {actual.get('author_name')}"
        assert actual.get("institution_name") == expected["institution_name"], f"Mismatch at index {i}: expected institution_name {expected['institution_name']}, got {actual.get('institution_name')}"
        assert actual.get("total_citations") == expected["total_citations"], f"Mismatch at index {i}: expected total_citations {expected['total_citations']}, got {actual.get('total_citations')}"
        assert actual.get("institution_rank") == expected["institution_rank"], f"Mismatch at index {i}: expected institution_rank {expected['institution_rank']}, got {actual.get('institution_rank')}"


def run_program():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"Compiled metrics program failed:\n{result.stderr}"
    assert os.path.isfile(JSON_PATH), "The compiled program did not create metrics_output.json."


def strip_cpp_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    return source


@pytest.fixture(scope="session", autouse=True)
def compile_and_exercise_submission():
    assert os.path.isfile(SOURCE_PATH), f"C++ source missing at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = strip_cpp_comments(f.read())

    assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", source, re.I), \
        "metrics.cpp must use the SQL RANK() window function."
    assert re.search(r"\bPARTITION\s+BY\b", source, re.I), \
        "The SQL window must partition authors by institution."

    if os.path.lexists(BINARY_PATH):
        os.remove(BINARY_PATH)
    build = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert build.returncode == 0, f"metrics.cpp did not compile:\n{build.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), \
        "Compilation did not produce an executable metrics binary."

    # First verify the program, rather than a pre-created JSON file, on the supplied DB.
    run_program()
    assert_json_matches(load_actual_json(), compute_expected_metrics())

    # Exercise the compiled artifact on an augmented dataset unknown to the submission.
    # The added tie checks true RANK semantics, zero citations checks LEFT JOIN behavior,
    # and the unrelated citation exposes an implicit citations cross join.
    fd, backup = tempfile.mkstemp(prefix="research_data_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup)
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        institution_id = cur.execute("SELECT COALESCE(MAX(id),0)+1000 FROM institutions").fetchone()[0]
        author_base = cur.execute("SELECT COALESCE(MAX(id),0)+1000 FROM authors").fetchone()[0]
        paper_base = cur.execute("SELECT COALESCE(MAX(id),0)+1000 FROM papers").fetchone()[0]
        citing_base = cur.execute("SELECT COALESCE(MAX(citing_paper_id),0)+1000 FROM citations").fetchone()[0]
        nonce = str(os.getpid())
        institution_name = "Dynamic Institute " + nonce
        names = ["Dynamic Tie A " + nonce, "Dynamic Tie B " + nonce, "Dynamic Zero " + nonce]

        cur.execute("INSERT INTO institutions(id,name) VALUES (?,?)", (institution_id, institution_name))
        for offset, name in enumerate(names):
            cur.execute("INSERT INTO authors(id,name,institution_id) VALUES (?,?,?)", (author_base + offset, name, institution_id))
            cur.execute("INSERT INTO papers(id,title) VALUES (?,?)", (paper_base + offset, "Dynamic Paper " + str(offset)))
            cur.execute("INSERT INTO authorships(author_id,paper_id) VALUES (?,?)", (author_base + offset, paper_base + offset))
        for offset in (0, 1):
            cur.execute("INSERT INTO citations VALUES (?,?)", (citing_base + offset * 10, paper_base + offset))
            cur.execute("INSERT INTO citations VALUES (?,?)", (citing_base + offset * 10 + 1, paper_base + offset))
        cur.execute("INSERT INTO citations VALUES (?,?)", (citing_base + 99, paper_base + 99999))
        conn.commit()
        conn.close()

        expected_dynamic = compute_expected_metrics()
        run_program()
        assert_json_matches(load_actual_json(), expected_dynamic)
        dynamic_rows = [x for x in expected_dynamic if x["institution_name"] == institution_name]
        assert [x["institution_rank"] for x in dynamic_rows] == [1, 1, 3]
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
        # Leave the requested output corresponding to the original database.
        run_program()


def test_json_output_correctness():
    assert_json_matches(load_actual_json(), compute_expected_metrics())


def parse_properties(body):
    props = {}
    pos = 0
    item = re.compile(r'''\s*([A-Za-z_]\w*)\s*:\s*((?:"(?:\\.|[^"\\])*")|(?:'(?:\\.|[^'\\])*')|-?\d+)\s*''')
    while pos < len(body):
        match = item.match(body, pos)
        assert match, f"Malformed Cypher property map near: {body[pos:]}"
        key, raw = match.groups()
        assert key not in props, f"Duplicate Cypher property {key}."
        props[key] = ast.literal_eval(raw) if raw[0] in "\"'" else int(raw)
        pos = match.end()
        if pos == len(body):
            break
        assert body[pos] == ',', f"Malformed Cypher property map near: {body[pos:]}"
        pos += 1
    return props


def parse_cypher(content):
    # Comments are permitted, but every non-comment token must belong to one of
    # the required executable clauses.
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    content = re.sub(r"//[^\n]*", "", content)
    inst_re = re.compile(r'''\s*(MERGE|CREATE)\s*\(\s*([A-Za-z_]\w*)\s*:\s*Institution\s*\{([^{}]*)\}\s*\)''', re.I)
    author_re = re.compile(r'''\s*CREATE\s*\(\s*([A-Za-z_]\w*)\s*:\s*Author\s*\{([^{}]*)\}\s*\)''', re.I)
    rel_re = re.compile(r'''\s*CREATE\s*\(\s*([A-Za-z_]\w*)\s*\)\s*-\s*\[\s*:\s*WORKS_AT\s*\]\s*->\s*\(\s*([A-Za-z_]\w*)\s*\)''', re.I)

    clauses = []
    pos = 0
    while True:
        separator = re.match(r"[\s;]*", content[pos:])
        pos += separator.end()
        if pos == len(content):
            break
        for kind, pattern in (("institution", inst_re), ("author", author_re), ("relationship", rel_re)):
            match = pattern.match(content, pos)
            if match:
                clauses.append((kind, match.groups()))
                pos = match.end()
                break
        else:
            pytest.fail(f"Malformed or unsupported Cypher near: {content[pos:pos+120]}")

    assert len(clauses) % 3 == 0, "Each author must have an Institution, Author, and WORKS_AT clause."
    blocks = []
    for index in range(0, len(clauses), 3):
        inst, author, rel = clauses[index:index + 3]
        assert inst[0] == "institution" and author[0] == "author" and rel[0] == "relationship", \
            "Each author block must create/merge an Institution, create an Author, then create WORKS_AT."
        _, inst_var, inst_body = inst[1]
        author_var, author_body = author[1]
        rel_author_var, rel_inst_var = rel[1]
        assert rel_author_var == author_var and rel_inst_var == inst_var, \
            "WORKS_AT must connect the Author and Institution variables from its block."
        inst_props = parse_properties(inst_body)
        author_props = parse_properties(author_body)
        assert set(inst_props) == {"name"}, "Institution nodes must have exactly a name property."
        assert set(author_props) == {"name", "total_citations"}, \
            "Author nodes must have exactly name and total_citations properties."
        blocks.append({
            "author_name": author_props["name"],
            "institution_name": inst_props["name"],
            "total_citations": author_props["total_citations"],
        })
    return blocks


def test_cypher_output_correctness():
    assert os.path.exists(CYPHER_PATH), f"Cypher output file missing at {CYPHER_PATH}"

    expected_metrics = compute_expected_metrics()
    top_authors = [m for m in expected_metrics if m["institution_rank"] == 1]

    with open(CYPHER_PATH, "r", encoding="utf-8") as f:
        cypher_content = f.read()

    # Preserve the original content assertions.
    for author in top_authors:
        assert author["author_name"] in cypher_content, f"Missing author {author['author_name']} in Cypher script."
        assert author["institution_name"] in cypher_content, f"Missing institution {author['institution_name']} in Cypher script."
        assert str(author["total_citations"]) in cypher_content, f"Missing total_citations {author['total_citations']} for {author['author_name']} in Cypher script."

    non_top_authors = [m for m in expected_metrics if m["institution_rank"] > 1]
    for author in non_top_authors:
        assert author["author_name"] not in cypher_content, f"Author {author['author_name']} has rank {author['institution_rank']} but was found in Cypher script."

    assert "MERGE " in cypher_content.upper() or "CREATE " in cypher_content.upper(), "Cypher script lacks MERGE or CREATE statements."
    assert "WORKS_AT" in cypher_content, "Cypher script lacks WORKS_AT relationship."

    # Parse every clause and compare complete node/relationship semantics, so
    # names or numbers hidden in malformed text cannot satisfy the verifier.
    actual_blocks = parse_cypher(cypher_content)
    expected_blocks = [
        {
            "author_name": author["author_name"],
            "institution_name": author["institution_name"],
            "total_citations": author["total_citations"],
        }
        for author in top_authors
    ]
    assert len(actual_blocks) == len(expected_blocks), \
        f"Expected exactly {len(expected_blocks)} top-author blocks, found {len(actual_blocks)}."
    assert sorted(actual_blocks, key=lambda x: (x["author_name"], x["institution_name"])) == \
           sorted(expected_blocks, key=lambda x: (x["author_name"], x["institution_name"])), \
        "Cypher author, institution, citation, or relationship data is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
