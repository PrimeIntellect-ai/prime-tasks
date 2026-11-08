#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess


def test_script_exists_and_executable():
    script_path = "/home/user/query_graph.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"

    # Check if executable
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"


def test_results_csv_exists_and_correct():
    results_path = "/home/user/results.csv"
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"

    expected_content = """user_id,user_name,product_id,product_name,purchase_date
U3,Charlie,P4,Smartphone,2023-10-10
U2,Bob,P1,Laptop,2023-10-02
U1,Alice,P1,Laptop,2023-10-01"""

    with open(results_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {results_path} does not match expected output.\nExpected:\n{expected_content}\n\nActual:\n{content}"


def run_script():
    proc = subprocess.run(
        ["/home/user/query_graph.sh"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f"query_graph.sh exited with status {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )


def expected_from_graph(nodes_path, edges_path):
    with open(nodes_path, newline="") as f:
        nodes = {row["node_id"]: row for row in csv.DictReader(f)}
    with open(edges_path, newline="") as f:
        edges = list(csv.DictReader(f))

    belongs = {}
    for edge in edges:
        if edge["rel_type"] == "BELONGS_TO":
            belongs.setdefault(edge["source_id"], []).append(edge["target_id"])

    rows = []
    for edge in edges:
        if edge["rel_type"] != "PURCHASED":
            continue
        user = nodes.get(edge["source_id"])
        product = nodes.get(edge["target_id"])
        if not user or not product:
            continue
        if user["node_label"] != "User" or product["node_label"] != "Product":
            continue
        try:
            expensive = float(product["attr2"]) > 500
        except ValueError:
            expensive = False
        if not expensive:
            continue
        for category_id in belongs.get(product["node_id"], []):
            category = nodes.get(category_id)
            if category and category["node_label"] == "Category" and category["attr1"] == "Electronics":
                rows.append([
                    user["node_id"], user["attr1"],
                    product["node_id"], product["attr1"], edge["rel_attr"],
                ])

    rows.sort(key=lambda row: row[4], reverse=True)
    lines = ["user_id,user_name,product_id,product_name,purchase_date"]
    lines.extend(",".join(row) for row in rows)
    return "\n".join(lines)


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def test_script_executes_and_processes_changed_inputs():
    nodes_path = "/home/user/nodes.csv"
    edges_path = "/home/user/edges.csv"
    results_path = "/home/user/results.csv"

    with open(nodes_path, "rb") as f:
        original_nodes = f.read()
    with open(edges_path, "rb") as f:
        original_edges = f.read()
    original_results = None
    if os.path.exists(results_path):
        with open(results_path, "rb") as f:
            original_results = f.read()

    token = secrets.token_hex(5)
    u1, u2, u3 = [f"U{token}{n}" for n in range(1, 4)]
    p1, p2, p3, p4 = [f"P{token}{n}" for n in range(1, 5)]
    ce, cf = f"CE{token}", f"CF{token}"

    base_nodes = [
        [u1, "User", f"Ada{token}", "31"],
        [u2, "User", f"Ben{token}", "44"],
        [u3, "User", f"Cy{token}", "27"],
        [p1, "Product", f"Monitor{token}", "725.50"],
        [p2, "Product", f"Cable{token}", "19.99"],
        [p3, "Product", f"Chair{token}", "910"],
        [p4, "Product", f"Tablet{token}", "650"],
        [ce, "Category", "Electronics", f"Devices{token}"],
        [cf, "Category", "Furniture", f"Home{token}"],
    ]

    edges_a = [
        [u1, p1, "PURCHASED", "2025-01-07"],
        [u2, p4, "PURCHASED", "2025-04-19"],
        [u3, p2, "PURCHASED", "2025-05-21"],
        [u1, p3, "PURCHASED", "2025-06-23"],
        [p1, ce, "BELONGS_TO", ""],
        [p2, ce, "BELONGS_TO", ""],
        [p3, cf, "BELONGS_TO", ""],
        [p4, ce, "BELONGS_TO", ""],
    ]

    edges_b = [
        [u1, p3, "PURCHASED", "2026-02-03"],
        [u2, p1, "PURCHASED", "2026-03-04"],
        [u3, p4, "PURCHASED", "2026-01-05"],
        [u1, p2, "PURCHASED", "2026-04-06"],
        [p1, ce, "BELONGS_TO", ""],
        [p2, ce, "BELONGS_TO", ""],
        [p3, cf, "BELONGS_TO", ""],
        [p4, ce, "BELONGS_TO", ""],
    ]

    swapped_nodes = [row[:] for row in base_nodes]
    for row in swapped_nodes:
        if row[0] == ce:
            row[2] = "Furniture"
        elif row[0] == cf:
            row[2] = "Electronics"

    try:
        # First ensure executing the artifact reproduces the supplied graph result.
        run_script()
        original_expected = """user_id,user_name,product_id,product_name,purchase_date
U3,Charlie,P4,Smartphone,2023-10-10
U2,Bob,P1,Laptop,2023-10-02
U1,Alice,P1,Laptop,2023-10-01"""
        with open(results_path) as f:
            assert f.read().strip() == original_expected

        # Exercise changed edges, then changed nodes with the same edges. Expected
        # answers are independently derived from each generated graph.
        for nodes, edges in (
            (base_nodes, edges_a),
            (base_nodes, edges_b),
            (swapped_nodes, edges_b),
        ):
            write_csv(nodes_path, ["node_id", "node_label", "attr1", "attr2"], nodes)
            write_csv(edges_path, ["source_id", "target_id", "rel_type", "rel_attr"], edges)
            expected = expected_from_graph(nodes_path, edges_path)
            run_script()
            assert os.path.isfile(results_path), "Script did not create /home/user/results.csv"
            with open(results_path) as f:
                actual = f.read().strip()
            assert actual == expected, (
                f"Incorrect output for generated graph.\nExpected:\n{expected}\n\nActual:\n{actual}"
            )
    finally:
        with open(nodes_path, "wb") as f:
            f.write(original_nodes)
        with open(edges_path, "wb") as f:
            f.write(original_edges)
        if original_results is None:
            if os.path.exists(results_path):
                os.remove(results_path)
        else:
            with open(results_path, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
