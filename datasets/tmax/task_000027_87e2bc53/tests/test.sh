#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path


def test_scripts_exist_and_executable():
    """Test that the required scripts exist and have execute permissions."""
    setup_script = "/home/user/setup_index.sh"
    query_script = "/home/user/query_traversal.sh"

    assert os.path.exists(setup_script), f"Script {setup_script} is missing."
    assert os.path.isfile(setup_script), f"Path {setup_script} is not a file."
    assert os.access(setup_script, os.X_OK), f"Script {setup_script} is not executable."

    assert os.path.exists(query_script), f"Script {query_script} is missing."
    assert os.path.isfile(query_script), f"Path {query_script} is not a file."
    assert os.access(query_script, os.X_OK), f"Script {query_script} is not executable."


def test_setup_index_execution_and_output():
    """Test that setup_index.sh creates the correct index files."""
    setup_script = "/home/user/setup_index.sh"
    index_dir = "/home/user/graph_index"

    result = subprocess.run([setup_script], capture_output=True, text=True)
    assert result.returncode == 0, f"setup_index.sh failed with return code {result.returncode}. stderr: {result.stderr}"

    assert os.path.exists(index_dir), f"Directory {index_dir} was not created."
    assert os.path.isdir(index_dir), f"Path {index_dir} is not a directory."

    a_txt_path = os.path.join(index_dir, "A.txt")
    assert os.path.exists(a_txt_path), f"File {a_txt_path} was not created."

    with open(a_txt_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = ["B", "C", "D", "I"]
    assert content == expected_content, f"Content of {a_txt_path} is incorrect. Expected {expected_content}, got {content}."


def test_query_traversal_execution_and_output():
    """Test that query_traversal.sh produces the correct output for node A."""
    query_script = "/home/user/query_traversal.sh"

    result = subprocess.run([query_script, "A"], capture_output=True, text=True)
    assert result.returncode == 0, f"query_traversal.sh failed with return code {result.returncode}. stderr: {result.stderr}"

    output_lines = result.stdout.strip().splitlines()
    expected_lines = [
        "E,4",
        "F,2",
        "J,1"
    ]

    assert output_lines == expected_lines, f"Output of query_traversal.sh is incorrect. Expected {expected_lines}, got {output_lines}."


def test_general_indexing_and_traversal_on_unseen_graph():
    setup_script = "/home/user/setup_index.sh"
    query_script = "/home/user/query_traversal.sh"
    network_path = Path("/home/user/network.tsv")
    index_dir = Path("/home/user/graph_index")

    token = secrets.token_hex(6)
    labels = [f"N_{token}_{i:02d}" for i in range(14)]
    secrets.SystemRandom().shuffle(labels)

    role_edges = [
        (0, 1), (0, 2), (0, 3), (0, 4),
        (1, 5), (1, 6), (1, 7), (1, 0), (1, 4),
        (2, 5), (2, 6), (2, 8), (2, 4),
        (3, 5), (3, 9), (3, 8),
        (4, 10), (4, 11), (4, 12),
        (5, 10), (5, 11),
        (6, 10), (6, 12),
        (7, 11), (7, 13),
        (8, 12), (8, 13),
        (9, 10), (9, 13),
        (10, 0), (10, 11),
        (11, 2), (11, 12),
        (12, 3), (12, 13),
        (13, 1),
    ]
    edges = [(labels[src], labels[dst]) for src, dst in role_edges]

    adjacency = {}
    for src, dst in edges:
        adjacency.setdefault(src, set()).add(dst)

    network_path.write_text("".join(f"{src}\t{dst}\n" for src, dst in edges))
    if index_dir.exists():
        shutil.rmtree(index_dir)

    result = subprocess.run([setup_script], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"setup_index.sh failed on an unseen graph. stderr: {result.stderr}"
    assert index_dir.is_dir(), "setup_index.sh did not create graph_index for the unseen graph."

    expected_files = {f"{src}.txt" for src in adjacency}
    actual_files = {p.name for p in index_dir.iterdir() if p.is_file()}
    assert actual_files == expected_files, f"Incorrect index file set. Expected {expected_files}, got {actual_files}."

    for src, targets in adjacency.items():
        index_file = index_dir / f"{src}.txt"
        assert index_file.is_file(), f"Missing index file for source {src}."
        actual_targets = index_file.read_text().splitlines()
        expected_targets = sorted(targets)
        assert actual_targets == expected_targets, (
            f"Incorrect index for {src}. Expected {expected_targets}, got {actual_targets}."
        )

    # The traversal is required to use the generated index, not rescan network.tsv.
    network_path.write_text(f"POISON_{token}\tOTHER_{token}\n")

    def expected_output(start):
        direct = set(adjacency.get(start, set()))
        counts = {}
        for intermediate in direct:
            for destination in set(adjacency.get(intermediate, set())):
                if destination == start or destination in direct:
                    continue
                counts[destination] = counts.get(destination, 0) + 1
        ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:5]
        return [f"{node},{count}" for node, count in ranked]

    for start in labels:
        result = subprocess.run(
            [query_script, start], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"query_traversal.sh failed for unseen start {start}. stderr: {result.stderr}"
        )
        actual = result.stdout.strip().splitlines()
        expected = expected_output(start)
        assert actual == expected, (
            f"Incorrect traversal output for {start}. Expected {expected}, got {actual}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
