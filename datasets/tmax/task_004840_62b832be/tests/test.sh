#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid


def test_part1_audio_extraction():
    root_info_path = "/home/user/root_info.txt"
    assert os.path.isfile(root_info_path), f"File missing: {root_info_path}"

    with open(root_info_path, "r") as f:
        content = f.read().strip()

    expected_content = "Root: Gamma, Score: 82"
    assert content == expected_content, f"Expected '{expected_content}', but got '{content}'"


def test_part2_adversarial_graph_filter():
    script_path = "/home/user/graph_filter.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"

    clean_files = os.listdir(clean_corpus_dir) if os.path.isdir(clean_corpus_dir) else []
    evil_files = os.listdir(evil_corpus_dir) if os.path.isdir(evil_corpus_dir) else []

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        for f in clean_files:
            shutil.copy(os.path.join(clean_corpus_dir, f), os.path.join(input_dir, f"clean_{f}"))

        for f in evil_files:
            shutil.copy(os.path.join(evil_corpus_dir, f), os.path.join(input_dir, f"evil_{f}"))

        result = subprocess.run(
            ["python3", script_path, input_dir, output_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"

        output_files = set(os.listdir(output_dir))

        clean_modified = []
        for f in clean_files:
            target_name = f"clean_{f}"
            if target_name not in output_files:
                clean_modified.append(target_name)
            else:
                with open(os.path.join(clean_corpus_dir, f), "r") as orig_f:
                    orig_data = json.load(orig_f)
                with open(os.path.join(output_dir, target_name), "r") as out_f:
                    try:
                        out_data = json.load(out_f)
                        if orig_data != out_data:
                            clean_modified.append(target_name)
                    except json.JSONDecodeError:
                        clean_modified.append(target_name)

        evil_bypassed = []
        for f in evil_files:
            target_name = f"evil_{f}"
            if target_name in output_files:
                evil_bypassed.append(target_name)

        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified or missing: {', '.join(clean_modified)}")

        if errors:
            assert False, " | ".join(errors)


def oracle_accepts(edges):
    nodes = set()
    adjacency = {}
    indegree = {}
    for edge in edges:
        source = edge["source"]
        target = edge["target"]
        nodes.update((source, target))
        adjacency.setdefault(source, set())
        adjacency.setdefault(target, set())
        indegree.setdefault(source, 0)
        indegree.setdefault(target, 0)
        if target not in adjacency[source]:
            adjacency[source].add(target)
            indegree[target] += 1

    queue = [node for node in nodes if indegree[node] == 0]
    distance = {node: 0 for node in nodes}
    processed = 0
    while queue:
        node = queue.pop()
        processed += 1
        for target in adjacency[node]:
            distance[target] = max(distance[target], distance[node] + 1)
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)

    if processed != len(nodes):
        return False
    return max(distance.values(), default=0) <= 10


def randomized_edges(integer_edges):
    ids = sorted({node for edge in integer_edges for node in edge})
    labels = {node: f"n_{secrets.token_hex(10)}" for node in ids}
    shuffled = list(integer_edges)
    secrets.SystemRandom().shuffle(shuffled)
    return [{"source": labels[source], "target": labels[target]} for source, target in shuffled]


def test_part2_generated_opaque_graphs():
    script_path = "/home/user/graph_filter.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    chain_1 = [(i, i + 1) for i in range(1)]
    chain_10 = [(i, i + 1) for i in range(10)]
    chain_11 = [(i, i + 1) for i in range(11)]
    wide_dag = [(0, i) for i in range(1, 31)]
    layered_dag = [
        (layer * 4 + left, (layer + 1) * 4 + right)
        for layer in range(5)
        for left in range(4)
        for right in range(4)
    ]
    short_cycle = [(0, 1), (1, 2), (2, 0)]
    self_cycle = [(0, 0)]
    disconnected_cycle = [(0, 1), (1, 2), (10, 11), (11, 12), (12, 10)]
    cycle_with_tail = [(i, i + 1) for i in range(7)] + [(7, 4)]
    branching_depth_10 = [(i, i + 1) for i in range(10)] + [(i, 100 + i) for i in range(10)]

    cases = [
        chain_1,
        chain_10,
        chain_11,
        wide_dag,
        layered_dag,
        short_cycle,
        self_cycle,
        disconnected_cycle,
        cycle_with_tail,
        branching_depth_10,
    ]

    rng = secrets.SystemRandom()
    for _ in range(12):
        count = rng.randint(6, 18)
        dag = [(i, j) for i in range(count) for j in range(i + 1, count) if rng.random() < 0.18]
        if not dag:
            dag = [(0, 1)]
        cases.append(dag)

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        expected = {}
        original_bytes = {}

        for integer_edges in cases:
            edges = randomized_edges(integer_edges)
            filename = f"{uuid.uuid4().hex}.json"
            path = os.path.join(input_dir, filename)
            payload = (json.dumps(edges, indent=rng.choice([None, 2, 4]), separators=None) + "\n").encode()
            with open(path, "wb") as f:
                f.write(payload)
            original_bytes[filename] = payload
            if oracle_accepts(edges):
                expected[filename] = payload

        result = subprocess.run(
            ["python3", script_path, input_dir, output_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"

        actual_names = set(os.listdir(output_dir))
        expected_names = set(expected)
        assert actual_names == expected_names, (
            f"Incorrect accepted files; missing={sorted(expected_names - actual_names)}, "
            f"unexpected={sorted(actual_names - expected_names)}"
        )

        for filename, expected_bytes in expected.items():
            output_path = os.path.join(output_dir, filename)
            assert os.path.isfile(output_path), f"Output is not a regular file: {filename}"
            with open(output_path, "rb") as f:
                actual_bytes = f.read()
            assert actual_bytes == expected_bytes, f"Clean file was not copied unmodified: {filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
