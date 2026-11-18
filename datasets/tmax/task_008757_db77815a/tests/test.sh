#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess

import matplotlib.image as mpimg
import pytest

NOTEBOOK = "/home/user/assembly.ipynb"
SEQUENCES = "/home/user/sequences.txt"
HUB = "/home/user/hub_sequence.txt"
GRAPH = "/home/user/graph.png"
ORIGINAL = [
    "AAACTAG",
    "TAGCCCA",
    "TAGGGGA",
    "TAGTTTA",
    "GATTACA",
    "ACAGCTA",
    "CTAGGAC",
]


def load_notebook():
    assert os.path.exists(NOTEBOOK), f"Notebook not found at {NOTEBOOK}"
    try:
        with open(NOTEBOOK, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Notebook {NOTEBOOK} is not valid JSON.")


def write_sequences(sequences):
    with open(SEQUENCES, "w", encoding="utf-8") as f:
        f.write("\n".join(sequences) + "\n")


def execute_notebook():
    for path in (HUB, GRAPH):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ["jupyter", "nbconvert", "--execute", "--to", "notebook", "--inplace", NOTEBOOK],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, "Notebook execution failed:\n" + result.stdout
    assert os.path.exists(HUB), "Executed notebook did not generate hub_sequence.txt"
    assert os.path.exists(GRAPH), "Executed notebook did not generate graph.png"


def expected_hub(sequences):
    # Nodes are sequence strings, so duplicate input lines represent one node.
    nodes = list(dict.fromkeys(sequences))
    degrees = {
        a: sum(1 for b in nodes if a != b and a[-3:] == b[:3])
        for a in nodes
    }
    best_degree = max(degrees.values())
    winners = [node for node in nodes if degrees[node] == best_degree]
    assert len(winners) == 1, "Verifier generated an ambiguous hub dataset"
    return winners[0]


def read_hub():
    with open(HUB, "r", encoding="utf-8") as f:
        return f.read().strip()


def validate_png():
    assert os.path.exists(GRAPH), f"Graph image not found at {GRAPH}"
    assert os.path.getsize(GRAPH) > 0, "Graph image file exists but is empty."
    with open(GRAPH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "graph.png is not a PNG file"
    try:
        image = mpimg.imread(GRAPH)
    except Exception as exc:
        pytest.fail(f"graph.png is not a readable image: {exc}")
    assert image.ndim in (2, 3), "graph.png has invalid pixel data"
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "graph.png is only a dummy-sized image"
    with open(GRAPH, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def random_dataset(extra_count):
    rng = secrets.SystemRandom()
    alphabet = "ACGT"
    while True:
        key = "".join(rng.choice(alphabet) for _ in range(3))
        hub = "".join(rng.choice(alphabet) for _ in range(6)) + key
        sequences = [hub]
        for _ in range(4):
            sequences.append(key + "".join(rng.choice(alphabet) for _ in range(6)))
        for _ in range(extra_count):
            sequences.append("".join(rng.choice(alphabet) for _ in range(9)))
        if len(set(sequences)) != len(sequences):
            continue
        degrees = {
            a: sum(1 for b in sequences if a != b and a[-3:] == b[:3])
            for a in sequences
        }
        maximum = max(degrees.values())
        if degrees[hub] == maximum and list(degrees.values()).count(maximum) == 1:
            rng.shuffle(sequences)
            return sequences


def test_notebook_exists_and_executed():
    """The submitted notebook itself must already have been executed."""
    nb_data = load_notebook()
    executed = False
    for cell in nb_data.get("cells", []):
        if cell.get("cell_type") == "code":
            count = cell.get("execution_count")
            if isinstance(count, int) and count > 0:
                executed = True
                break
    assert executed, "Notebook was not executed properly (no valid execution counts found)."

    source = "\n".join(
        "".join(cell.get("source", []))
        for cell in nb_data.get("cells", [])
        if cell.get("cell_type") == "code"
    )
    assert re.search(r"(^|\n)\s*(import\s+networkx|from\s+networkx\s+import)", source), \
        "Notebook code does not import networkx"
    assert "DiGraph" in source, "Notebook code does not construct a directed networkx graph"
    assert "savefig" in source, "Notebook code does not save a matplotlib visualization"


def test_workflow_reexecutes_on_original_input():
    write_sequences(ORIGINAL)
    execute_notebook()
    nb_data = load_notebook()
    nonempty_code = [
        cell for cell in nb_data.get("cells", [])
        if cell.get("cell_type") == "code" and "".join(cell.get("source", [])).strip()
    ]
    assert nonempty_code, "Notebook contains no code cells"
    assert all(isinstance(c.get("execution_count"), int) and c["execution_count"] > 0
               for c in nonempty_code), "Not all nonempty code cells were executed"


def test_hub_sequence_file():
    assert os.path.exists(HUB), f"Hub sequence file not found at {HUB}"
    hub_seq = read_hub()
    assert hub_seq == "AAACTAG", f"Incorrect hub sequence found: {hub_seq}. Expected 'AAACTAG'."


def test_graph_image_exists():
    validate_png()


def test_notebook_computes_unseen_overlap_graphs():
    baseline_hash = validate_png()
    image_hashes = [baseline_hash]
    try:
        for extra_count in (7, 13):
            sequences = random_dataset(extra_count)
            expected = expected_hub(sequences)
            write_sequences(sequences)
            execute_notebook()
            assert read_hub() == expected, \
                "Notebook did not compute the highest out-degree sequence for an unseen input"
            image_hashes.append(validate_png())
        assert len(set(image_hashes)) == len(image_hashes), \
            "graph.png did not change when the overlap graph changed"
    finally:
        write_sequences(ORIGINAL)
        execute_notebook()

    assert read_hub() == "AAACTAG"
    validate_png()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
