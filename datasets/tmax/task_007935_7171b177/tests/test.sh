#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_program.py
import csv
import os
import secrets
import stat
import subprocess
from collections import deque

HOME = "/home/user"
DATA = os.path.join(HOME, "data")
ENTITIES = os.path.join(DATA, "entities.csv")
RELATIONSHIPS = os.path.join(DATA, "relationships.csv")
SOURCE = os.path.join(HOME, "analyze.go")
OUTPUTS = [os.path.join(HOME, "shortest_path.txt"), os.path.join(HOME, "page2.txt")]


def clear_outputs():
    for path in OUTPUTS:
        if os.path.lexists(path):
            os.remove(path)


def run_program():
    clear_outputs()
    result = subprocess.run(
        ["go", "run", SOURCE],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"go run failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for path in OUTPUTS:
        assert os.path.isfile(path), f"Program did not create {path}"


def derive_expected():
    names = {}
    with open(ENTITIES, newline="") as f:
        for row in csv.DictReader(f):
            names[row["id"]] = row["name"]

    graph = {entity_id: [] for entity_id in names}
    with open(RELATIONSHIPS, newline="") as f:
        for row in csv.DictReader(f):
            if row["relationship_type"] == "owns" and float(row["ownership_percentage"]) > 50:
                graph.setdefault(row["parent_id"], []).append(row["child_id"])

    start = next(entity_id for entity_id, name in names.items() if name == "Apex_Holdings")
    target = next(entity_id for entity_id, name in names.items() if name == "Zeta_Retail")

    queue = deque([start])
    previous = {start: None}
    while queue:
        current = queue.popleft()
        if current == target:
            break
        for child in graph.get(current, []):
            if child not in previous:
                previous[child] = current
                queue.append(child)

    assert target in previous, "Verifier-generated graph unexpectedly has no target path"
    path = []
    current = target
    while current is not None:
        path.append(names[current])
        current = previous[current]
    path.reverse()

    reachable = sorted(names[entity_id] for entity_id in previous if entity_id != start)
    return ",".join(path), reachable[2:4]


def check_dynamic_outputs():
    expected_path, expected_page = derive_expected()
    with open(OUTPUTS[0]) as f:
        actual_path = f.read().strip()
    with open(OUTPUTS[1]) as f:
        actual_page = [line.strip() for line in f if line.strip()]
    assert actual_path == expected_path, f"Expected dynamic shortest path {expected_path!r}, got {actual_path!r}"
    assert actual_page == expected_page, f"Expected dynamic page 2 {expected_page!r}, got {actual_page!r}"


source_stat = os.lstat(SOURCE)
assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} must be a regular Go source file"

with open(ENTITIES, "rb") as f:
    original_entities = f.read()
with open(RELATIONSHIPS, "rb") as f:
    original_relationships = f.read()

suffixes = [secrets.token_hex(6) for _ in range(9)]
entity_rows = [
    ["10", "Apex_Holdings", "Holding"],
    ["11", "Node_" + suffixes[0], "Manufacturing"],
    ["12", "Node_" + suffixes[1], "Logistics"],
    ["13", "Node_" + suffixes[2], "Retail"],
    ["14", "Node_" + suffixes[3], "Tech"],
    ["15", "Node_" + suffixes[4], "Services"],
    ["16", "Zeta_Retail", "Retail"],
    ["17", "Filtered_" + suffixes[5], "Shell"],
    ["18", "Supplied_" + suffixes[6], "Other"],
    ["19", "Case_" + suffixes[7], "Other"],
]
relationship_rows = [
    ["10", "11", "owns", "100"],
    ["11", "12", "owns", "51"],
    ["12", "16", "owns", "52"],
    ["10", "13", "owns", "99"],
    ["13", "14", "owns", "70"],
    ["14", "15", "owns", "80"],
    ["15", "16", "owns", "90"],
    ["12", "14", "owns", "60"],
    ["14", "10", "owns", "100"],
    ["10", "17", "owns", "50"],
    ["17", "16", "owns", "100"],
    ["10", "18", "supplies", "100"],
    ["10", "19", "OWNS", "100"],
]

try:
    with open(ENTITIES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "industry"])
        writer.writerows(entity_rows)
    with open(RELATIONSHIPS, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["parent_id", "child_id", "relationship_type", "ownership_percentage"])
        writer.writerows(relationship_rows)

    run_program()
    check_dynamic_outputs()
finally:
    with open(ENTITIES, "wb") as f:
        f.write(original_entities)
    with open(RELATIONSHIPS, "wb") as f:
        f.write(original_relationships)

# Re-run against the original inputs so the original final-state assertions check
# files actually produced by the submitted Go program.
run_program()
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_shortest_path_file():
    path = '/home/user/shortest_path.txt'
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected = "Apex_Holdings,Bravo_Corp,Delta_LLC,Zeta_Retail"
    assert content == expected, f"Expected shortest path '{expected}', but got '{content}'"

def test_page2_file():
    path = '/home/user/page2.txt'
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = ["Delta_LLC", "Echo_Group"]
    assert lines == expected, f"Expected page 2 entities {expected}, but got {lines}"
TEST_EOF

if python3 /tmp/verify_program.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
