#!/bin/bash
set -u
mkdir -p /logs/verifier

WORKDIR=$(mktemp -d)
cp -a /home/user/dataset "$WORKDIR/dataset"
if [ -f /home/user/top_authors.json ]; then
    cp /home/user/top_authors.json "$WORKDIR/top_authors.json"
fi

cleanup() {
    rm -rf /home/user/dataset
    cp -a "$WORKDIR/dataset" /home/user/dataset
    if [ -f "$WORKDIR/top_authors.json" ]; then
        cp "$WORKDIR/top_authors.json" /home/user/top_authors.json
    else
        rm -f /home/user/top_authors.json
    fi
    rm -rf "$WORKDIR"
}

run_checks() {
    test -f /home/user/process_graph.cpp || {
        echo "The C++ source file /home/user/process_graph.cpp does not exist."
        return 1
    }

    g++ -std=c++17 /home/user/process_graph.cpp -o "$WORKDIR/process_graph" || return 1
    test -x "$WORKDIR/process_graph" || return 1

    # Require the submitted program itself to generate the result for the original data.
    rm -f /home/user/top_authors.json
    timeout 20 "$WORKDIR/process_graph" || return 1

    cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
import os
import json
import pytest

def test_process_graph_cpp_exists():
    cpp_file = "/home/user/process_graph.cpp"
    assert os.path.isfile(cpp_file), f"The C++ source file {cpp_file} does not exist."

def test_top_authors_json_exists_and_valid():
    json_file = "/home/user/top_authors.json"
    assert os.path.isfile(json_file), f"The output file {json_file} does not exist."

    with open(json_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {json_file}: {e}")

    assert isinstance(data, list), "The JSON root should be a list."
    assert len(data) == 3, f"Expected exactly 3 authors in the JSON, but found {len(data)}."

    expected_data = [
        {"author_id": 1, "name": "Alice", "centrality": 6},
        {"author_id": 2, "name": "Bob", "centrality": 3},
        {"author_id": 3, "name": "Charlie", "centrality": 3}
    ]

    for i, expected in enumerate(expected_data):
        assert data[i] == expected, f"Mismatch at index {i}. Expected {expected}, got {data[i]}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short || return 1

    # Exercise the binary on fresh inputs and derive the expected answer independently.
    for case_num in 1 2; do
        CASE_NUM="$case_num" python3 - << 'PY_EOF' || return 1
import csv
import json
import os
import secrets

rng = secrets.SystemRandom()
case_num = int(os.environ["CASE_NUM"])
ids = rng.sample(range(1000, 9000), 9)
names = [f"Author_{case_num}_{secrets.token_hex(4)}" for _ in ids]

# A nontrivial collaboration topology; IDs, names, and CSV row order vary each run.
papers = [
    [0, 1, 2],
    [0, 3],
    [1, 4, 5],
    [2, 5],
    [3, 4, 6],
    [0, 6, 7],
    [7, 8],
    [1, 3, 8],
]

author_rows = list(zip(ids, names))
rng.shuffle(author_rows)
with open("/home/user/dataset/authors.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["author_id", "name"])
    writer.writerows(author_rows)

paper_rows = []
for offset, members in enumerate(papers):
    paper_id = 50000 + case_num * 100 + offset
    for index in members:
        paper_rows.append((paper_id, ids[index]))
rng.shuffle(paper_rows)
with open("/home/user/dataset/paper_authors.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["paper_id", "author_id"])
    writer.writerows(paper_rows)

coauthors = {author_id: set() for author_id in ids}
for members in papers:
    member_ids = [ids[index] for index in members]
    for author_id in member_ids:
        coauthors[author_id].update(other for other in member_ids if other != author_id)

name_by_id = dict(zip(ids, names))
ranked = sorted(ids, key=lambda author_id: (-len(coauthors[author_id]), author_id))[:3]
expected = [
    {
        "author_id": author_id,
        "name": name_by_id[author_id],
        "centrality": len(coauthors[author_id]),
    }
    for author_id in ranked
]
with open("/tmp/expected_top_authors.json", "w") as f:
    json.dump(expected, f)
PY_EOF

        rm -f /home/user/top_authors.json
        timeout 20 "$WORKDIR/process_graph" || return 1

        python3 - << 'PY_EOF' || return 1
import json
import os

output_path = "/home/user/top_authors.json"
assert os.path.isfile(output_path), "Program did not create top_authors.json"
with open(output_path) as f:
    actual = json.load(f)
with open("/tmp/expected_top_authors.json") as f:
    expected = json.load(f)
assert isinstance(actual, list), "The JSON root should be a list."
assert len(actual) == 3, f"Expected exactly 3 authors, got {len(actual)}."
assert actual == expected, f"Expected {expected}, got {actual}."
PY_EOF
    done
}

if run_checks; then
    reward=1
else
    reward=0
fi

cleanup
echo "$reward" > /logs/verifier/reward.txt
