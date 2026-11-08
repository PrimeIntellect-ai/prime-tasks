#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import pytest

BASE_DIR = "/home/user/data_migration"
NODES_DIR = os.path.join(BASE_DIR, "nodes")


def run_checked(argv, **kwargs):
    try:
        return subprocess.run(argv, capture_output=True, text=True, check=True, **kwargs)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Command failed: {argv}\nstdout: {e.stdout}\nstderr: {e.stderr}")


def transform(value):
    return (value ^ 0x5A) + 12


def expected_result(order, values):
    acc = 0
    lines = []
    for name in order:
        lines.append(f"Processed: {name}")
        acc = (acc * 3 + transform(values[name])) % 100000
    lines.append(f"Final Accumulator: {acc}")
    return lines


def read_result():
    result_file = os.path.join(BASE_DIR, "result.txt")
    assert os.path.isfile(result_file), f"Missing result file: {result_file}"
    with open(result_file) as f:
        return [line.strip() for line in f if line.strip()]


def test_cmake_and_build():
    cmake_file = os.path.join(BASE_DIR, "c_src", "CMakeLists.txt")
    assert os.path.isfile(cmake_file), f"Missing file: {cmake_file}"

    with open(cmake_file, "r") as f:
        content = f.read()
        assert "target_link_libraries" in content and not content.startswith("# target_link_libraries"), "CMakeLists.txt does not link libraries properly."

    # Reconfigure and rebuild from source, rather than trusting a supplied executable.
    build_dir = os.path.join(BASE_DIR, "c_src", "build")
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir)
    run_checked(["cmake", ".."], cwd=build_dir)
    run_checked(["make"], cwd=build_dir)

    calc_node_exec = os.path.join(build_dir, "calc_node")
    assert os.path.isfile(calc_node_exec), f"Missing executable: {calc_node_exec}"
    for value in (0, 10, 37, 1234):
        result = run_checked([calc_node_exec, str(value)])
        assert result.stdout.strip() == str(transform(value)), f"calc_node produced incorrect output for {value}: {result.stdout.strip()}"


def test_python_parser_migrated():
    parser_file = os.path.join(BASE_DIR, "dag_parser.py")
    assert os.path.isfile(parser_file), f"Missing file: {parser_file}"

    with open(parser_file, "r") as f:
        content = f.read()
        assert "print(" in content or "print (" in content, "dag_parser.py still contains Python 2 print statements."
        assert "xrange" not in content, "dag_parser.py still contains Python 2 xrange."

    test_node = os.path.join(NODES_DIR, "leaf1.node")
    result = run_checked(["python3", parser_file, test_node])
    assert "VALUE: 10" in result.stdout, "dag_parser.py did not output the correct VALUE."

    # Exercise the unchanged CLI on fresh metadata, including dependency order.
    with tempfile.NamedTemporaryFile(mode="w", suffix=".node", dir=NODES_DIR, delete=False) as f:
        f.write("DEPS: second.node, first.node\nVALUE: 37\n")
        path = f.name
    try:
        result = run_checked(["python3", parser_file, path])
        output = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert "VALUE: 37" in output
        assert "DEPS: second.node,first.node" in output
    finally:
        os.unlink(path)


def test_process_graph_script_and_results():
    script_file = os.path.join(BASE_DIR, "process_graph.sh")
    assert os.path.isfile(script_file), f"Missing file: {script_file}"
    assert os.access(script_file, os.X_OK), f"{script_file} is not executable."

    # First retain the original root-graph assertion, but generate result.txt by
    # actually executing the submitted orchestrator.
    root = os.path.join(NODES_DIR, "root.node")
    run_checked([script_file, root], cwd=BASE_DIR)
    expected_lines = [
        "Processed: leaf1",
        "Processed: child1",
        "Processed: leaf2",
        "Processed: child2",
        "Processed: root",
        "Final Accumulator: 11555",
    ]
    assert read_result() == expected_lines

    # Create a distinct DAG to verify post-order, dependency ordering, de-duplication,
    # arbitrary start paths, transformed values, and accumulator calculation.
    case_dir = tempfile.mkdtemp(prefix="verifier_graph_", dir=NODES_DIR)
    try:
        files = {
            "start": "DEPS: left.node, right.node\nVALUE: 31\n",
            "left": "DEPS: shared.node, lone.node\nVALUE: 7\n",
            "right": "DEPS: shared.node\nVALUE: 44\n",
            "shared": "DEPS:\nVALUE: 13\n",
            "lone": "DEPS:\nVALUE: 2\n",
        }
        for name, body in files.items():
            with open(os.path.join(case_dir, name + ".node"), "w") as f:
                f.write(body)

        run_checked([script_file, os.path.join(case_dir, "start.node")], cwd=BASE_DIR)
        order = ["shared", "lone", "left", "right", "start"]
        values = {"start": 31, "left": 7, "right": 44, "shared": 13, "lone": 2}
        assert read_result() == expected_result(order, values)
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
