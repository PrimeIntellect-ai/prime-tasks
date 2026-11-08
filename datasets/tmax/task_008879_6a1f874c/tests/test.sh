#!/bin/bash
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp /home/user/data/nodes.csv "$BACKUP_DIR/nodes.csv"
cp /home/user/data/edges.csv "$BACKUP_DIR/edges.csv"
HAD_OUTPUT=0
if [ -f /home/user/output.json ]; then
    HAD_OUTPUT=1
    cp /home/user/output.json "$BACKUP_DIR/output.json"
fi

cleanup() {
    mkdir -p /home/user/data
    cp "$BACKUP_DIR/nodes.csv" /home/user/data/nodes.csv
    cp "$BACKUP_DIR/edges.csv" /home/user/data/edges.csv
    if [ "$HAD_OUTPUT" -eq 1 ]; then
        cp "$BACKUP_DIR/output.json" /home/user/output.json
    else
        rm -f /home/user/output.json
    fi
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_output_json_exists_and_correct():
    """Check if output.json exists, is valid JSON, and contains the correct results."""
    output_file = "/home/user/output.json"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. The Rust program must create this file."

    with open(output_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} is not valid JSON.")

    assert "highest_degree_name" in data, "Missing 'highest_degree_name' key in JSON output."
    assert "total_edges" in data, "Missing 'total_edges' key in JSON output."
    assert "total_triangles" in data, "Missing 'total_triangles' key in JSON output."

    expected_name = "Charlie"
    expected_edges = 8
    expected_triangles = 3

    assert data["highest_degree_name"] == expected_name, f"Expected highest_degree_name to be '{expected_name}', got '{data['highest_degree_name']}'."
    assert data["total_edges"] == expected_edges, f"Expected total_edges to be {expected_edges}, got {data['total_edges']}."
    assert data["total_triangles"] == expected_triangles, f"Expected total_triangles to be {expected_triangles}, got {data['total_triangles']}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import csv
import json
import os
import random
import subprocess

NODES = "/home/user/data/nodes.csv"
EDGES = "/home/user/data/edges.csv"
OUTPUT = "/home/user/output.json"
RUNNER = "/tmp/run_graph_submission.sh"


def compute_expected():
    id_to_name = {}
    with open(NODES, newline="") as f:
        for row in csv.reader(f):
            id_to_name[int(row[2])] = row[0]

    valid_ids = set(id_to_name)
    unique_edges = set()
    with open(EDGES, newline="") as f:
        for row in csv.reader(f):
            a, b = int(row[2]), int(row[3])
            if a not in valid_ids or b not in valid_ids or a == b:
                continue
            unique_edges.add(tuple(sorted((a, b))))

    neighbors = {node: set() for node in valid_ids}
    for a, b in unique_edges:
        neighbors[a].add(b)
        neighbors[b].add(a)

    max_degree = max(len(neighbors[node]) for node in valid_ids)
    winners = [node for node in valid_ids if len(neighbors[node]) == max_degree]
    assert len(winners) == 1, "Verifier fixture unexpectedly has a degree tie"

    triangles = 0
    ordered = sorted(valid_ids)
    for i, a in enumerate(ordered):
        for j in range(i + 1, len(ordered)):
            b = ordered[j]
            if b not in neighbors[a]:
                continue
            for k in range(j + 1, len(ordered)):
                c = ordered[k]
                if c in neighbors[a] and c in neighbors[b]:
                    triangles += 1

    return {
        "highest_degree_name": id_to_name[winners[0]],
        "total_edges": len(unique_edges),
        "total_triangles": triangles,
    }


def write_case(center, graph_edges, node_count):
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 900000), node_count)
    names = [f"Person_{rng.randrange(10**9):09d}_{i}" for i in range(node_count)]
    ages = rng.sample(range(20, 90), node_count)

    with open(NODES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        for name, age, user_id in zip(names, ages, ids):
            writer.writerow([name, age, user_id])

    rows = []
    timestamp = 1700000000 + rng.randrange(1000000)
    for index, (a, b) in enumerate(graph_edges):
        rows.append([timestamp + index, f"{rng.random():.6f}", ids[a], ids[b]])
    # Duplicate/reversed communications, a self-loop, and an edge to a nonexistent user.
    a, b = graph_edges[0]
    rows.append([timestamp + 100, "0.123456", ids[b], ids[a]])
    rows.append([timestamp + 101, "0.654321", ids[center], ids[center]])
    invalid_id = max(ids) + 1000003
    rows.append([timestamp + 102, "0.500000", ids[center], invalid_id])
    rng.shuffle(rows)

    with open(EDGES, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)


def run_and_check():
    expected = compute_expected()
    try:
        os.remove(OUTPUT)
    except FileNotFoundError:
        pass
    subprocess.run([RUNNER], check=True, timeout=45)
    assert os.path.isfile(OUTPUT), "Rust program did not create output.json"
    with open(OUTPUT) as f:
        actual = json.load(f)
    for key, value in expected.items():
        assert key in actual, f"Missing {key!r} in dynamically generated result"
        assert actual[key] == value, f"For generated CSV data, {key} should be {value!r}, got {actual[key]!r}"


# A six-spoke hub plus three edges among leaves: the hub is the unique degree winner.
case_one = [(0, i) for i in range(1, 7)] + [(1, 2), (2, 3), (1, 3)]
write_case(0, case_one, 7)
run_and_check()

# A different hub position and graph shape prevents a fixed-output implementation.
case_two = [(4, i) for i in range(6) if i != 4] + [(0, 1), (1, 2)]
write_case(4, case_two, 6)
run_and_check()
DYNAMIC_EOF

verify_submission() {
    rm -f /tmp/graph_analyzer_bin /tmp/run_graph_submission.sh

    if [ -f /home/user/graph_analyzer.rs ] && [ -s /home/user/graph_analyzer.rs ] && \
       rustc /home/user/graph_analyzer.rs -O -o /tmp/graph_analyzer_bin; then
        cat << 'RUN_EOF' > /tmp/run_graph_submission.sh
#!/bin/bash
cd /home/user
exec /tmp/graph_analyzer_bin
RUN_EOF
    elif [ -f /home/user/graph_project/Cargo.toml ] && \
         find /home/user/graph_project -type f -name '*.rs' -print -quit | grep -q . && \
         cargo build --quiet --manifest-path /home/user/graph_project/Cargo.toml; then
        cat << 'RUN_EOF' > /tmp/run_graph_submission.sh
#!/bin/bash
cd /home/user
exec cargo run --quiet --manifest-path /home/user/graph_project/Cargo.toml
RUN_EOF
    else
        echo "No compilable Rust submission was found." >&2
        return 1
    fi
    chmod +x /tmp/run_graph_submission.sh

    # Delete any prewritten answer and require the compiled Rust artifact to recreate it.
    rm -f /home/user/output.json
    timeout 45 /tmp/run_graph_submission.sh || return 1

    # Preserve all assertions from the original verifier on the supplied data.
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Re-run the artifact on fresh graphs and independently recompute their answers.
    python3 /tmp/test_dynamic.py || return 1
    return 0
}

if verify_submission 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
