#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess

NODES = "/home/user/backup_nodes.csv"
EDGES = "/home/user/backup_edges.csv"
SOURCE = "/home/user/analyze_backup.c"
BINARY = "/home/user/analyze_backup"
OUTPUT = "/home/user/critical_node.txt"
QUERY = "/home/user/validation_query.cypher"

ORIGINAL_NODES = """id,label
1,Server
2,Router
3,Switch
4,Database
5,Firewall
"""
ORIGINAL_EDGES = """source,target,type
1,3,CONNECTED_TO
2,3,CONNECTED_TO
4,3,CONNECTED_TO
5,2,ROUTED_THROUGH
5,1,SECURES
1,4,QUERIES
"""


def write_fixture(node_ids, edges):
    with open(NODES, "w") as f:
        f.write("id,label\n")
        for node_id in node_ids:
            f.write(f"{node_id},Node{node_id}\n")
    with open(EDGES, "w") as f:
        f.write("source,target,type\n")
        for source, target in edges:
            f.write(f"{source},{target},CONNECTED_TO\n")


def expected_result(node_ids, edges):
    degrees = {node_id: 0 for node_id in node_ids}
    for source, target in edges:
        degrees[source] += 1
        degrees[target] += 1
    return min(node_ids, key=lambda node_id: (-degrees[node_id], node_id)), max(degrees.values())


def run_case(executable, node_ids, edges):
    write_fixture(node_ids, edges)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{executable} did not create {OUTPUT}."

    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    expected_id, expected_degree = expected_result(node_ids, edges)
    assert content == f"{expected_id},{expected_degree}", (
        f"For the supplied CSV data, expected '{expected_id},{expected_degree}' "
        f"but {executable} produced '{content}'."
    )


def restore_original_and_run():
    with open(NODES, "w") as f:
        f.write(ORIGINAL_NODES)
    with open(EDGES, "w") as f:
        f.write(ORIGINAL_EDGES)
    subprocess.run([BINARY], cwd="/home/user", stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, timeout=10)


def test_c_source_code_exists():
    file_path = SOURCE
    assert os.path.exists(file_path), f"C source file {file_path} is missing."


def test_compiled_executable_exists_and_executable():
    file_path = BINARY
    assert os.path.exists(file_path), f"Compiled executable {file_path} is missing."
    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{file_path} is not a compiled ELF executable."


def test_program_reads_and_analyzes_csv_files():
    rebuilt = "/tmp/analyze_backup_from_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"The submitted C source does not compile: {compile_result.stderr}"
    )

    rng = random.SystemRandom()
    random_ids = sorted(rng.sample(range(100, 1000000), 9))
    random_edges = []
    for _ in range(27):
        source, target = rng.sample(random_ids, 2)
        random_edges.append((source, target))

    cases = [
        ([1, 2, 3, 4, 5], [(1, 3), (2, 3), (4, 3), (5, 2), (5, 1), (1, 4)]),
        ([10, 2, 7, 99], [(2, 7), (2, 99), (10, 7), (10, 99)]),
        ([42, 8, 17, 63, 91], [(42, 8), (17, 42), (42, 63), (91, 42), (8, 17)]),
        ([31, 4, 88], []),
        (random_ids, random_edges),
    ]

    try:
        for executable in (BINARY, rebuilt):
            for node_ids, edges in cases:
                run_case(executable, node_ids, edges)
    finally:
        restore_original_and_run()


def test_critical_node_output():
    with open(NODES, "w") as f:
        f.write(ORIGINAL_NODES)
    with open(EDGES, "w") as f:
        f.write(ORIGINAL_EDGES)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([BINARY], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, result.stderr

    file_path = OUTPUT
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "1,3", f"Expected '1,3' in {file_path}, but got '{content}'."


def test_cypher_query_validation():
    file_path = QUERY
    assert os.path.exists(file_path), f"Cypher query file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().upper()

    # Preserve the original checks.
    assert "MATCH" in content, "Cypher query is missing MATCH clause."
    assert "ORDER BY" in content, "Cypher query is missing ORDER BY clause."
    assert "DESC" in content, "Cypher query is missing DESC ordering."
    assert "LIMIT 1" in content, "Cypher query is missing LIMIT 1."
    assert "COUNT" in content, "Cypher query is missing COUNT function."

    # Ignore comments so a list of keywords in comments cannot satisfy semantics.
    query = re.sub(r"/\*.*?\*/", " ", content, flags=re.S)
    query = re.sub(r"//[^\n]*", " ", query)
    query = re.sub(r"\s+", " ", query).strip()

    undirected = re.search(
        r"\(\s*([A-Z_][A-Z0-9_]*)[^)]*\)\s*-\s*(?:\[[^]]*\])?\s*-\s*\(",
        query
    )
    assert undirected, "The query must count relationships using an undirected pattern."
    node_var = undirected.group(1)

    assert re.search(r"\bAS\s+TOTAL_DEGREE\b", query), (
        "The relationship count must be aliased as total_degree."
    )
    assert "OPTIONAL MATCH" in query or re.search(r"\bCOUNT\s*\{", query), (
        "The query must retain nodes with zero relationships."
    )

    returned = re.search(r"\bRETURN\b(.*?)\bORDER\s+BY\b", query)
    assert returned, "The query must RETURN results before ORDER BY."
    return_clause = returned.group(1)
    assert re.search(rf"\b{re.escape(node_var)}\s*\.\s*ID\b", return_clause), (
        "The query must return the node's id property."
    )
    assert re.search(r"\bTOTAL_DEGREE\b", return_clause), (
        "The query must return total_degree."
    )

    ordering = re.search(r"\bORDER\s+BY\b(.*?)\bLIMIT\s+1\b", query)
    assert ordering, "ORDER BY must precede LIMIT 1."
    order_clause = ordering.group(1)
    degree_order = re.search(r"\bTOTAL_DEGREE\b\s+DESC\b", order_clause)
    id_order = re.search(
        rf"(?:\b{re.escape(node_var)}\s*\.\s*ID\b|\bID\b|TOINTEGER\s*\(\s*{re.escape(node_var)}\s*\.\s*ID\s*\))\s+ASC\b",
        order_clause
    )
    assert degree_order, "The query must order total_degree descending."
    assert id_order, "The query must resolve ties by id ascending."
    assert degree_order.start() < id_order.start(), (
        "total_degree descending must be the primary order and id ascending the tie-breaker."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
