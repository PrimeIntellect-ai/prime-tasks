#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import runpy
import sqlite3
import uuid
from pathlib import Path

import rdflib

SCRIPT_PATH = Path('/home/user/process_data.py')
JSON_PATH = Path('/home/user/ai_authors.json')
TTL_PATH = Path('/home/user/datasets/topics.ttl')
DB_PATH = Path('/home/user/datasets/authors.db')


def test_ai_authors_json_exists_and_correct():
    json_path = "/home/user/ai_authors.json"
    assert os.path.isfile(json_path), f"Expected output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    expected_data = {
        "Ada Lovelace": [
            "Advanced LLMs",
            "Notes on the Analytical Engine"
        ],
        "Alan Turing": [
            "Computing Machinery and Intelligence",
            "Deep Neural Nets",
            "The Imitation Game"
        ]
    }

    assert isinstance(data, dict), "The top-level JSON structure should be a dictionary/object."
    assert set(data.keys()) == set(expected_data.keys()), f"Expected authors {list(expected_data.keys())}, but got {list(data.keys())}."

    for author, expected_papers in expected_data.items():
        actual_papers = data.get(author)
        assert isinstance(actual_papers, list), f"The value for '{author}' must be a list of strings."
        assert actual_papers == sorted(actual_papers), f"The paper titles for '{author}' are not sorted alphabetically."
        assert actual_papers == expected_papers, f"Expected papers {expected_papers} for '{author}', but got {actual_papers}."


def test_json_formatting():
    json_path = "/home/user/ai_authors.json"
    assert os.path.isfile(json_path), f"Expected output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        content = f.read()

    assert "\n" in content, "The JSON file should be nicely formatted (e.g., indent=2), but no newlines were found."


def test_script_executes_sparql_recursion_and_sql_join_on_new_data():
    assert SCRIPT_PATH.is_file(), f"Expected Python script {SCRIPT_PATH} does not exist."

    original_ttl = TTL_PATH.read_bytes()
    original_db = DB_PATH.read_bytes()
    original_json = JSON_PATH.read_bytes() if JSON_PATH.exists() else None

    token = uuid.uuid4().hex
    base = f"http://example.org/dynamic/{token}/"
    target = "http://example.org/topics/ArtificialIntelligence"
    level1 = base + "LevelOne"
    level2 = base + "LevelTwo"
    level3 = base + "LevelThree"
    unrelated = base + "Unrelated"

    author_a = f"Dynamic Author A {token}"
    author_b = f"Dynamic Author B {token}"
    author_c = f"Excluded Author {token}"

    authors = [(11, author_a), (22, author_b), (33, author_c)]
    papers = [
        (1, f"Zeta Target {token}", 11, target),
        (2, f"Alpha Deep {token}", 11, level3),
        (3, f"Middle Branch {token}", 22, level1),
        (4, f"Excluded Biology {token}", 33, unrelated),
        (5, f"Beta Deep {token}", 11, level2),
    ]
    matched_topics = {target, level1, level2, level3}
    names = dict(authors)
    expected = {}
    for _, title, author_id, topic_uri in papers:
        if topic_uri in matched_topics:
            expected.setdefault(names[author_id], []).append(title)
    expected = {name: sorted(titles) for name, titles in expected.items()}

    sparql_queries = []
    sql_statements = []
    real_graph_query = rdflib.Graph.query
    real_connect = sqlite3.connect

    class CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor

        def execute(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            self._cursor.execute(statement, *args, **kwargs)
            return self

        def executemany(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            self._cursor.executemany(statement, *args, **kwargs)
            return self

        def executescript(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            self._cursor.executescript(statement, *args, **kwargs)
            return self

        def __iter__(self):
            return iter(self._cursor)

        def __next__(self):
            return next(self._cursor)

        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class ConnectionProxy:
        def __init__(self, connection):
            self._connection = connection

        def cursor(self, *args, **kwargs):
            return CursorProxy(self._connection.cursor(*args, **kwargs))

        def execute(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            return CursorProxy(self._connection.execute(statement, *args, **kwargs))

        def executemany(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            return CursorProxy(self._connection.executemany(statement, *args, **kwargs))

        def executescript(self, statement, *args, **kwargs):
            sql_statements.append(str(statement))
            return CursorProxy(self._connection.executescript(statement, *args, **kwargs))

        def __enter__(self):
            self._connection.__enter__()
            return self

        def __exit__(self, *args):
            return self._connection.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self._connection, name)

    def traced_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs))

    def traced_graph_query(graph, query_object, *args, **kwargs):
        sparql_queries.append(str(query_object))
        return real_graph_query(graph, query_object, *args, **kwargs)

    try:
        TTL_PATH.write_text(
            '@prefix ex: <http://example.org/topics/> .\n'
            '@prefix dyn: <' + base + '> .\n'
            '@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n\n'
            'ex:ArtificialIntelligence a rdfs:Class .\n'
            'dyn:LevelOne rdfs:subClassOf ex:ArtificialIntelligence .\n'
            'dyn:LevelTwo rdfs:subClassOf dyn:LevelOne .\n'
            'dyn:LevelThree rdfs:subClassOf dyn:LevelTwo .\n'
            'dyn:Unrelated a rdfs:Class .\n',
            encoding='utf-8'
        )

        DB_PATH.unlink()
        connection = real_connect(str(DB_PATH))
        connection.executescript(
            'CREATE TABLE authors (author_id INTEGER PRIMARY KEY, name TEXT);'
            'CREATE TABLE papers (paper_id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, topic_uri TEXT);'
        )
        connection.executemany('INSERT INTO authors (author_id, name) VALUES (?, ?)', authors)
        connection.executemany('INSERT INTO papers (paper_id, title, author_id, topic_uri) VALUES (?, ?, ?, ?)', papers)
        connection.commit()
        connection.close()

        if JSON_PATH.exists():
            JSON_PATH.unlink()

        sqlite3.connect = traced_connect
        rdflib.Graph.query = traced_graph_query
        try:
            runpy.run_path(str(SCRIPT_PATH), run_name='__main__')
        except SystemExit as exc:
            assert exc.code in (None, 0), f"The script exited unsuccessfully with status {exc.code}."

        assert JSON_PATH.is_file(), "Executing process_data.py did not generate ai_authors.json."
        with JSON_PATH.open(encoding='utf-8') as handle:
            actual = json.load(handle)

        assert actual == expected, f"The script produced incorrect results for a new recursive fixture: {actual!r}"
        for titles in actual.values():
            assert titles == sorted(titles), "Generated paper-title arrays are not alphabetically sorted."

        assert sparql_queries, "process_data.py did not execute an rdflib SPARQL query."
        recursive_query_seen = any(
            'subclassof' in query.lower()
            and re.search(r'subclassof[^{}\n]{0,16}[*+]', query.lower())
            for query in sparql_queries
        )
        assert recursive_query_seen, "The executed SPARQL did not use a recursive rdfs:subClassOf property path."

        joined_query_seen = any(
            re.search(r'\bselect\b', statement, re.I)
            and re.search(r'\bjoin\b', statement, re.I)
            and re.search(r'\bauthors\b', statement, re.I)
            and re.search(r'\bpapers\b', statement, re.I)
            for statement in sql_statements
        )
        assert joined_query_seen, "process_data.py did not execute a SQL JOIN between papers and authors."
    finally:
        rdflib.Graph.query = real_graph_query
        sqlite3.connect = real_connect
        TTL_PATH.parent.mkdir(parents=True, exist_ok=True)
        TTL_PATH.write_bytes(original_ttl)
        DB_PATH.write_bytes(original_db)
        if original_json is None:
            if JSON_PATH.exists():
                JSON_PATH.unlink()
        else:
            JSON_PATH.write_bytes(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
