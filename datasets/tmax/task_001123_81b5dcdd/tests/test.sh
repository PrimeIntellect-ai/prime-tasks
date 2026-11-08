#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

def test_path_result():
    result_path = "/home/user/path_result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. You need to write the output of the program to this file."

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = "Quantum Entanglement Set,Photon Emission Data,Subatomic Scattering,Standard Model Results,Macroscopic Superposition Set"
    assert content == expected, f"Expected path result to be '{expected}', but got '{content}'"

def test_optimize_sql():
    sql_path = "/home/user/optimize.sql"
    assert os.path.isfile(sql_path), f"File {sql_path} is missing. You need to create this file with index creation statements."

    with open(sql_path, "r") as f:
        content = f.read().upper()

    assert "CREATE INDEX" in content, "optimize.sql must contain at least one CREATE INDEX statement."
    assert "DATASET_AUTHORS" in content, "optimize.sql must create an index on the dataset_authors table."

def test_cpp_parameterization():
    cpp_path = "/home/user/graph_search.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "sqlite3_bind_" in content, "The C++ file must use sqlite3_bind_* functions for proper parameterization."
    assert "SELECT b.dataset_id FROM dataset_authors a, dataset_authors b;" not in content, "The buggy implicit cross-join query is still present in the C++ file."

def test_database_indexes_applied():
    db_path = "/home/user/research_data.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='dataset_authors';")
    indexes = c.fetchall()
    conn.close()

    assert len(indexes) > 0, "No indexes found on the dataset_authors table in the database. Make sure you actually applied optimize.sql to the database."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
