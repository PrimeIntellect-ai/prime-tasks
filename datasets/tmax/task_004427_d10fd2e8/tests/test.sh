#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
import time


def mutate_database(db_path, params):
    node_mul, node_add, edge_mul, edge_add = params
    conn = sqlite3.connect(db_path)
    conn.execute('''
        UPDATE Nodes
        SET value = value * (
            0.55 + CAST(((id * ? + ?) % 901) AS REAL) / 1000.0
        )
        WHERE type = 'ARTICLE'
    ''', (node_mul, node_add))
    conn.execute('''
        UPDATE Edges
        SET weight = weight * (
            0.60 + CAST(((rowid * ? + ?) % 801) AS REAL) / 1000.0
        )
    ''', (edge_mul, edge_add))
    conn.commit()
    conn.close()


def generate_golden(db_path):
    conn = sqlite3.connect(db_path)
    rows = conn.execute('''
        SELECT n1.id, SUM(n3.value * e1.weight * e2.weight) AS score
        FROM Nodes n1
        JOIN Edges e1 ON n1.id = e1.source
        JOIN Edges e2 ON e1.target = e2.source
        JOIN Nodes n3 ON e2.target = n3.id
        WHERE n1.type = 'AUTHOR' AND n3.type = 'ARTICLE'
        GROUP BY n1.id
        ORDER BY score DESC, n1.id ASC
        LIMIT 100
    ''').fetchall()
    conn.close()
    return [f"{author_id},{score:.4f}" for author_id, score in rows]


def has_edges_source_index(db_path):
    conn = sqlite3.connect(db_path)
    indexes = conn.execute('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index' AND tbl_name = 'Edges' AND sql IS NOT NULL
    ''').fetchall()
    found = False
    for (name,) in indexes:
        escaped = name.replace("'", "''")
        columns = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
        if columns and columns[0][2] == 'source':
            found = True
            break
    conn.close()
    return found


def test_query_optimizer_performance_and_correctness():
    cpp_source = "/home/user/query_optimizer.cpp"
    binary_path = "/home/user/query_optimizer"
    results_csv = "/home/user/results.csv"
    generator_path = "/app/data_generator"
    work_dir = "/home/user"
    db_path = os.path.join(work_dir, "graph.db")

    assert os.path.exists(cpp_source), f"Source file {cpp_source} does not exist."

    compile_cmd = ["g++", "-O3", cpp_source, "-lsqlite3", "-o", binary_path]
    comp_res = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert comp_res.returncode == 0, f"Compilation failed:\n{comp_res.stderr}"
    assert os.path.exists(binary_path), "Compiled binary was not created."

    params = (
        secrets.randbelow(900000) + 100001,
        secrets.randbelow(1000000),
        secrets.randbelow(900000) + 100001,
        secrets.randbelow(1000000),
    )

    # Build a randomized reference instance and retain its answer only in memory.
    if os.path.exists(db_path):
        os.remove(db_path)
    gen_res = subprocess.run([generator_path], cwd=work_dir, capture_output=True)
    assert gen_res.returncode == 0, "Data generator failed."
    assert os.path.exists(db_path), "graph.db was not created by data generator."
    mutate_database(db_path, params)
    golden_lines = generate_golden(db_path)

    # Recreate the same randomized instance so index creation remains timed.
    os.remove(db_path)
    gen_res = subprocess.run([generator_path], cwd=work_dir, capture_output=True)
    assert gen_res.returncode == 0, "Data generator failed."
    assert os.path.exists(db_path), "graph.db was not created by data generator."
    mutate_database(db_path, params)

    if os.path.exists(results_csv):
        os.remove(results_csv)
    stale_golden = os.path.join(work_dir, "golden.csv")
    if os.path.exists(stale_golden):
        os.remove(stale_golden)

    start_time = time.time()
    exec_res = subprocess.run([binary_path], cwd=work_dir, capture_output=True)
    duration = time.time() - start_time

    assert exec_res.returncode == 0, f"Program execution failed with return code {exec_res.returncode}"
    assert os.path.exists(results_csv), f"Results file {results_csv} was not created."

    with open(results_csv, 'r') as result_file:
        agent_lines = [line.strip() for line in result_file if line.strip()]

    assert agent_lines == golden_lines, "The output CSV does not match the golden reference."
    assert has_edges_source_index(db_path), "No persistent index beginning with Edges.source was created."

    threshold = 1.5
    assert duration <= threshold, f"Execution time {duration:.4f}s exceeded the threshold of {threshold}s."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
