#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def run_script(script_path, start, deps_path):
    return subprocess.run(
        [script_path, start, deps_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def expected_closure(start, edges):
    children = {}
    for upstream, downstream in edges:
        children.setdefault(upstream, set()).add(downstream)

    impacted = set()
    pending = list(children.get(start, ()))
    while pending:
        node = pending.pop()
        if node in impacted:
            continue
        impacted.add(node)
        pending.extend(children.get(node, ()))
    return sorted(impacted)


def test_script_exists_and_executable():
    script_path = "/home/user/trace_lineage.sh"
    assert os.path.exists(script_path), f"Missing script: {script_path}"
    assert os.path.isfile(script_path), f"Expected {script_path} to be a file"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"


def test_impacted_ds_005_output():
    output_path = "/home/user/impacted_DS_005.txt"
    assert os.path.exists(output_path), f"Missing output file: {output_path}"

    expected_datasets = [
        "DS_006",
        "DS_007",
        "DS_010",
        "DS_011",
        "DS_012",
        "DS_013",
        "DS_014"
    ]

    with open(output_path, "r") as f:
        content = f.read().splitlines()

    content = [line.strip() for line in content if line.strip()]
    assert content == expected_datasets, (
        f"Contents of {output_path} are incorrect. "
        f"Expected {expected_datasets}, got {content}"
    )

    result = run_script(
        "/home/user/trace_lineage.sh",
        "DS_005",
        "/home/user/dataset_dependencies.tsv",
    )
    assert result.returncode == 0, (
        f"Script failed for DS_005 with return code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    generated = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert generated == content, (
        "Saved DS_005 output does not match output currently produced by the script. "
        f"Saved: {content}; generated: {generated}"
    )


def test_script_functionality_ds_001():
    script_path = "/home/user/trace_lineage.sh"
    deps_path = "/home/user/dataset_dependencies.tsv"

    result = run_script(script_path, "DS_001", deps_path)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. stderr: {result.stderr}"
    )

    expected_datasets = [
        "DS_002",
        "DS_003",
        "DS_004"
    ]

    output = result.stdout.splitlines()
    output = [line.strip() for line in output if line.strip()]
    assert output == expected_datasets, (
        f"Script output for DS_001 is incorrect. "
        f"Expected {expected_datasets}, got {output}"
    )


def test_dynamic_arbitrary_dags():
    script_path = "/home/user/trace_lineage.sh"

    for _ in range(4):
        nodes = [f"NODE_{secrets.token_hex(6)}" for _ in range(14)]

        # All edges point from a lower to a higher topological index, so the
        # generated graph is a DAG. It includes depth, branching, merging,
        # disconnected components, and a duplicate edge.
        edges = [
            (nodes[0], nodes[1]),
            (nodes[1], nodes[2]),
            (nodes[2], nodes[3]),
            (nodes[0], nodes[4]),
            (nodes[4], nodes[5]),
            (nodes[3], nodes[6]),
            (nodes[5], nodes[6]),
            (nodes[6], nodes[9]),
            (nodes[7], nodes[8]),
            (nodes[10], nodes[11]),
            (nodes[11], nodes[12]),
            (nodes[0], nodes[1]),
        ]
        for i in range(len(nodes)):
            for j in range(i + 1, len(nodes)):
                if secrets.randbelow(9) == 0:
                    edges.append((nodes[i], nodes[j]))

        # Randomize edge order so traversal cannot depend on grouped input.
        for i in range(len(edges) - 1, 0, -1):
            j = secrets.randbelow(i + 1)
            edges[i], edges[j] = edges[j], edges[i]

        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".tsv") as deps:
            deps.write("Upstream\tDownstream\n")
            for upstream, downstream in edges:
                deps.write(f"{upstream}\t{downstream}\n")
            deps_path = deps.name

        try:
            unknown = f"ABSENT_{secrets.token_hex(6)}"
            for start in (nodes[0], nodes[4], nodes[7], nodes[13], unknown):
                expected = expected_closure(start, edges)
                result = run_script(script_path, start, deps_path)
                assert result.returncode == 0, (
                    f"Script failed on generated DAG for {start}: {result.stderr}"
                )
                actual = result.stdout.splitlines()
                assert actual == expected, (
                    f"Incorrect output on generated DAG for {start}. "
                    f"Expected {expected}, got {actual}. stderr: {result.stderr}"
                )
        finally:
            os.unlink(deps_path)


def test_requires_exactly_two_arguments():
    script_path = "/home/user/trace_lineage.sh"
    deps_path = "/home/user/dataset_dependencies.tsv"

    too_few = subprocess.run(
        [script_path, "DS_001"], capture_output=True, text=True, timeout=10
    )
    assert too_few.returncode != 0, "Script accepted fewer than two arguments"

    too_many = subprocess.run(
        [script_path, "DS_001", deps_path, "extra"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert too_many.returncode != 0, "Script accepted more than two arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
