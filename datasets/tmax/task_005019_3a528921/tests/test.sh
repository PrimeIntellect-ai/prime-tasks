#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_source_file_exists():
    assert os.path.isfile('/home/user/analyze_graph.c'), "Source file /home/user/analyze_graph.c does not exist."


def test_compilation():
    # Compile the code to ensure we are testing the latest version
    result = subprocess.run(
        ['gcc', '/home/user/analyze_graph.c', '-o', '/home/user/analyze'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile('/home/user/analyze'), "Executable /home/user/analyze was not created."


def test_analyze_output_1():
    # Test case from the prompt: min_year=2018, page_size=3, page_number=2
    result = subprocess.run(
        ['/home/user/analyze', '2018', '3', '2'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Execution failed:\n{result.stderr}"

    expected_output = "p4,1\np7,1\np6,0"
    actual_output = result.stdout.strip()
    assert actual_output == expected_output, f"Expected output:\n{expected_output}\n\nGot:\n{actual_output}"


def test_analyze_output_2():
    # Test case: min_year=2019, page_size=2, page_number=1
    # Valid nodes: p3, p4, p5, p7
    # Valid edges: p7->p4, p7->p5, p4->p5, p3->p5
    # In-degrees: p5: 3, p4: 1, p3: 0, p7: 0
    # Sorted: p5,3 | p4,1 | p3,0 | p7,0
    # Page 1, size 2 -> p5,3 | p4,1
    result = subprocess.run(
        ['/home/user/analyze', '2019', '2', '1'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Execution failed:\n{result.stderr}"

    expected_output = "p5,3\np4,1"
    actual_output = result.stdout.strip()
    assert actual_output == expected_output, f"Expected output:\n{expected_output}\n\nGot:\n{actual_output}"


def test_analyze_output_3():
    # Test case: min_year=2022, page_size=5, page_number=1
    # Valid nodes: p7
    # Valid edges: none
    # In-degrees: p7: 0
    # Sorted: p7,0
    # Page 1, size 5 -> p7,0
    result = subprocess.run(
        ['/home/user/analyze', '2022', '5', '1'],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Execution failed:\n{result.stderr}"

    expected_output = "p7,0"
    actual_output = result.stdout.strip()
    assert actual_output == expected_output, f"Expected output:\n{expected_output}\n\nGot:\n{actual_output}"


def _expected(nodes, edges, min_year, page_size, page_number):
    included = {node_id for node_id, year in nodes if year >= min_year}
    degree = {node_id: 0 for node_id in included}
    for source, target in edges:
        if source in included and target in included:
            degree[target] += 1
    ordered = sorted(degree.items(), key=lambda item: (-item[1], item[0]))
    start = (page_number - 1) * page_size
    page = ordered[start:start + page_size]
    return '\n'.join(f'{node_id},{value}' for node_id, value in page)


def _write_graph(nodes, edges):
    with open('/home/user/nodes.csv', 'w', encoding='utf-8', newline='') as f:
        f.write('id,year\n')
        for node_id, year in nodes:
            f.write(f'{node_id},{year}\n')
    with open('/home/user/edges.csv', 'w', encoding='utf-8', newline='') as f:
        f.write('source,target\n')
        for source, target in edges:
            f.write(f'{source},{target}\n')


def _make_graph(count, salt):
    # Unpredictable IDs prevent a submission from hardcoding verifier outputs.
    nodes = [
        (f'paper_{secrets.token_hex(6)}_{i:02d}', 2014 + ((i * 5 + salt) % 11))
        for i in range(count)
    ]
    edges = []
    for i in range(count):
        for j in range(count):
            if i != j and ((i * 7 + j * 11 + salt) % 17) < 4:
                edges.append((nodes[i][0], nodes[j][0]))
    return nodes, edges


def test_runtime_generated_graphs_and_pagination():
    # Recompile here as well so this behavioral test does not depend on pytest order.
    compile_result = subprocess.run(
        ['gcc', '/home/user/analyze_graph.c', '-o', '/home/user/analyze'],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    with open('/home/user/nodes.csv', 'rb') as f:
        original_nodes = f.read()
    with open('/home/user/edges.csv', 'rb') as f:
        original_edges = f.read()

    try:
        scenarios = [_make_graph(29, 3), _make_graph(18, 9)]
        queries = [
            (2014, 4, 1),
            (2016, 7, 2),
            (2018, 3, 3),
            (2020, 5, 1),
            (2022, 2, 2),
            (2024, 9, 1),
            (2017, 6, 20),
        ]
        for nodes, edges in scenarios:
            _write_graph(nodes, edges)
            for min_year, page_size, page_number in queries:
                expected = _expected(nodes, edges, min_year, page_size, page_number)
                result = subprocess.run(
                    ['/home/user/analyze', str(min_year), str(page_size), str(page_number)],
                    capture_output=True, text=True, timeout=10
                )
                assert result.returncode == 0, (
                    f'Execution failed for {(min_year, page_size, page_number)}:\n{result.stderr}'
                )
                actual = result.stdout.strip()
                assert actual == expected, (
                    f'Generated graph failed for {(min_year, page_size, page_number)}. '
                    f'Expected:\n{expected}\n\nGot:\n{actual}'
                )
    finally:
        with open('/home/user/nodes.csv', 'wb') as f:
            f.write(original_nodes)
        with open('/home/user/edges.csv', 'wb') as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
