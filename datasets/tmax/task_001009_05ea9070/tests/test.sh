#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import sqlite3
import subprocess
import random
import pytest

ZONES = [
    "LOBBY", "HALL_1", "SERVER_ROOM", "CAFETARIA", "PATIO",
    "HALL_2", "HR_OFFICE", "EXEC_SUITE", "BACK_ALLEY", "IT_STORAGE",
    "SMOKING_AREA", "BALCONY", "SECURITY_DESK", "CAMERA_ROOM"
]

EDGES = [
    ("LOBBY", "HALL_1"), ("HALL_1", "SERVER_ROOM"), ("HALL_1", "CAFETARIA"),
    ("CAFETARIA", "PATIO"), ("LOBBY", "HALL_2"), ("HALL_2", "HR_OFFICE"),
    ("HR_OFFICE", "EXEC_SUITE"), ("SERVER_ROOM", "BACK_ALLEY"),
    ("HALL_2", "IT_STORAGE"), ("IT_STORAGE", "SERVER_ROOM"),
    ("PATIO", "SMOKING_AREA"), ("EXEC_SUITE", "BALCONY"),
    ("LOBBY", "SECURITY_DESK"), ("SECURITY_DESK", "CAMERA_ROOM"),
    ("CAMERA_ROOM", "SERVER_ROOM")
]

def get_graph():
    graph = {}
    for u, v in EDGES:
        graph.setdefault(u, set()).add(v)
        graph.setdefault(v, set()).add(u)
    return graph

def test_database_and_table_exists():
    db_path = "/home/user/audit.db"
    assert os.path.isfile(db_path), f"Database not found at {db_path}"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='doors';")
    assert cursor.fetchone() is not None, "Table 'doors' does not exist in the database."
    conn.close()

def test_database_indexes_exist():
    db_path = "/home/user/audit.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='doors';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on 'doors' table to optimize queries."
    conn.close()

def test_fuzz_equivalence_path_check():
    oracle_path = "/tests/oracle_path_check.py"
    student_path = "/home/user/path_check.py"

    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}"
    assert os.path.isfile(student_path), f"Student script missing at {student_path}"

    random.seed(42)
    graph = get_graph()

    for _ in range(50):
        start_zone = random.choice(ZONES)
        end_zone = random.choice(ZONES)
        oracle_result = subprocess.run([sys.executable, oracle_path, start_zone, end_zone], capture_output=True, text=True)
        student_result = subprocess.run([sys.executable, student_path, start_zone, end_zone], capture_output=True, text=True)

        assert oracle_result.returncode == 0, f"Oracle failed on {start_zone} to {end_zone}"
        assert student_result.returncode == 0, f"Student script failed (return code {student_result.returncode}) on {start_zone} to {end_zone}. Stderr: {student_result.stderr}"

        oracle_out = oracle_result.stdout.strip()
        student_out = student_result.stdout.strip()
        if oracle_out == "NO_PATH":
            assert student_out == "NO_PATH", f"Input: {start_zone} -> {end_zone}\nExpected: NO_PATH\nGot: {student_out}"
        else:
            oracle_path_list = oracle_out.split(",")
            student_path_list = student_out.split(",")
            assert len(student_path_list) == len(oracle_path_list), (
                f"Input: {start_zone} -> {end_zone}\nExpected path length {len(oracle_path_list)} ({oracle_out})\nGot path length {len(student_path_list)} ({student_out})"
            )
            assert student_path_list[0] == start_zone, f"Path must start with {start_zone}, got {student_path_list[0]}"
            assert student_path_list[-1] == end_zone, f"Path must end with {end_zone}, got {student_path_list[-1]}"
            for i in range(len(student_path_list) - 1):
                u = student_path_list[i]
                v = student_path_list[i + 1]
                assert u in graph and v in graph[u], f"Invalid transition in path: {u} -> {v}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
