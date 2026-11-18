#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze.sh"
DEGREES_PATH = "/home/user/degrees.csv"
PATHS_PATH = "/home/user/paths.csv"


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_analyze_script_logic():
    test_csv_content = """10,20
20,30
10,40
40,30
30,50
60,20
"""

    expected_degrees = """node,in_degree,out_degree
10,0,2
20,2,1
30,2,1
40,1,1
50,1,0
60,0,1
"""

    expected_paths = """a,b,c
10,20,30
10,40,30
20,30,50
40,30,50
60,20,30
"""

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv") as tmp:
        tmp.write(test_csv_content)
        tmp_path = tmp.name

    try:
        result = subprocess.run([SCRIPT_PATH, tmp_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"

        assert os.path.isfile(DEGREES_PATH), f"Output file {DEGREES_PATH} was not created."
        with open(DEGREES_PATH, "r") as f:
            degrees_content = f.read()
        assert degrees_content.strip() == expected_degrees.strip(), f"Content of {DEGREES_PATH} is incorrect.\nExpected:\n{expected_degrees}\nGot:\n{degrees_content}"

        assert os.path.isfile(PATHS_PATH), f"Output file {PATHS_PATH} was not created."
        with open(PATHS_PATH, "r") as f:
            paths_content = f.read()
        assert paths_content.strip() == expected_paths.strip(), f"Content of {PATHS_PATH} is incorrect.\nExpected:\n{expected_paths}\nGot:\n{paths_content}"
    finally:
        os.remove(tmp_path)


def expected_outputs(edges):
    nodes = sorted({node for edge in edges for node in edge})
    in_degree = {node: 0 for node in nodes}
    out_degree = {node: 0 for node in nodes}
    for source, target in edges:
        out_degree[source] += 1
        in_degree[target] += 1

    degree_lines = ["node,in_degree,out_degree"]
    degree_lines.extend(
        f"{node},{in_degree[node]},{out_degree[node]}" for node in nodes
    )

    paths = sorted(
        (source, middle, target)
        for source, middle in edges
        for next_middle, target in edges
        if middle == next_middle
    )
    path_lines = ["a,b,c"]
    path_lines.extend(f"{a},{b},{c}" for a, b, c in paths)
    return "\n".join(degree_lines), "\n".join(path_lines)


def run_generated_case(edges):
    expected_degrees, expected_paths = expected_outputs(edges)
    input_content = "\n".join(f"{source},{target}" for source, target in edges) + "\n"

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv") as tmp:
        tmp.write(input_content)
        tmp_path = tmp.name

    try:
        for output_path in (DEGREES_PATH, PATHS_PATH):
            if os.path.exists(output_path):
                os.remove(output_path)

        result = subprocess.run(
            [SCRIPT_PATH, tmp_path], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"Script failed on generated input with return code {result.returncode}.\n"
            f"Input:\n{input_content}\nStderr: {result.stderr}"
        )

        assert os.path.isfile(DEGREES_PATH), f"Output file {DEGREES_PATH} was not created."
        with open(DEGREES_PATH, "r") as f:
            actual_degrees = f.read().strip()
        assert actual_degrees == expected_degrees, (
            f"Incorrect degrees for generated input:\n{input_content}\n"
            f"Expected:\n{expected_degrees}\nGot:\n{actual_degrees}"
        )

        assert os.path.isfile(PATHS_PATH), f"Output file {PATHS_PATH} was not created."
        with open(PATHS_PATH, "r") as f:
            actual_paths = f.read().strip()
        assert actual_paths == expected_paths, (
            f"Incorrect paths for generated input:\n{input_content}\n"
            f"Expected:\n{expected_paths}\nGot:\n{actual_paths}"
        )
    finally:
        os.remove(tmp_path)


def test_analyze_script_on_unpredictable_graphs():
    rng = secrets.SystemRandom()
    for _ in range(5):
        node_count = rng.randint(5, 10)
        nodes = sorted(rng.sample(range(100, 1000000), node_count))

        # A cycle ensures every generated node occurs and that length-2 paths exist.
        edge_set = {
            (nodes[index], nodes[(index + 1) % node_count])
            for index in range(node_count)
        }
        candidates = [
            (source, target)
            for source in nodes
            for target in nodes
            if source != target and (source, target) not in edge_set
        ]
        rng.shuffle(candidates)
        extra_count = rng.randint(0, min(len(candidates), node_count + 8))
        edge_set.update(candidates[:extra_count])
        edges = list(edge_set)
        rng.shuffle(edges)
        run_generated_case(edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
