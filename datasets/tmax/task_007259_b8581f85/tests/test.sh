#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import json
import os
import subprocess


def test_analyze_graph_go_exists():
    path = "/home/user/analyze_graph.go"
    assert os.path.isfile(path), f"File {path} is missing. Did you create the Go program?"


def test_matches_json_correctness():
    path = "/home/user/matches.json"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the Go program to generate the output?"

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    assert isinstance(data, list), f"The JSON output in {path} must be a list (array)."

    expected_data = [
        {
            "company": "TechCorp",
            "industry": "AI",
            "person": "Alice"
        },
        {
            "company": "FutureAI",
            "industry": "AI",
            "person": "Bob"
        },
        {
            "company": "FutureAI",
            "industry": "AI",
            "person": "Charlie"
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} matches, but got {len(data)}."

    for i, expected_match in enumerate(expected_data):
        assert data[i] == expected_match, f"Match at index {i} is incorrect. Expected {expected_match}, got {data[i]}."


def test_matches_json_formatting():
    path = "/home/user/matches.json"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    # Check for 2-space indentation by looking at the first few lines
    lines = content.splitlines()
    if len(lines) > 2:
        # The second line should start with exactly two spaces and then a quote or brace
        assert lines[1].startswith("  ") and not lines[1].startswith("   "), "The JSON file does not appear to be formatted with 2-space indentation."


def derive_expected(nodes, edges):
    by_id = {row["id"]: row for row in nodes}
    expected = []
    for works in edges:
        if works["relation"] != "WORKS_FOR":
            continue
        person = by_id.get(works["source"])
        company = by_id.get(works["target"])
        if not person or not company or person["type"] != "Person" or company["type"] != "Company":
            continue
        for operates in edges:
            if operates["source"] != company["id"] or operates["relation"] != "OPERATES_IN":
                continue
            industry = by_id.get(operates["target"])
            if industry and industry["type"] == "Industry" and industry["name"] == "AI":
                expected.append({
                    "person": person["name"],
                    "company": company["name"],
                    "industry": industry["name"],
                })
    expected.sort(key=lambda item: item["person"])
    return expected


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def run_case(binary, nodes, edges):
    write_csv("/home/user/nodes.csv", ["id", "type", "name"], nodes)
    write_csv("/home/user/edges.csv", ["source", "target", "relation"], edges)
    if os.path.exists("/home/user/matches.json"):
        os.remove("/home/user/matches.json")

    result = subprocess.run([binary], cwd="/home/user", capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Compiled analyzer failed: {result.stderr or result.stdout}"
    assert os.path.isfile("/home/user/matches.json"), "The analyzer did not create matches.json."

    with open("/home/user/matches.json", "r") as f:
        content = f.read()
    try:
        actual = json.loads(content)
    except json.JSONDecodeError as exc:
        assert False, f"Analyzer produced invalid JSON: {exc}"

    expected = derive_expected(nodes, edges)
    assert isinstance(actual, list), "Analyzer output must be a JSON array."
    assert actual == expected, f"Analyzer output for changed CSV input was incorrect. Expected {expected}, got {actual}."
    for item in actual:
        assert set(item.keys()) == {"person", "company", "industry"}, f"Match has incorrect keys: {item}"
    assert [item["person"] for item in actual] == sorted(item["person"] for item in actual), "Matches are not sorted by person name."

    canonical = json.dumps(actual, indent=2, ensure_ascii=False)
    assert content.rstrip("\n") == canonical, "Analyzer output is not formatted with 2-space JSON indentation."


def test_go_program_compiles_and_analyzes_changed_inputs():
    source = "/home/user/analyze_graph.go"
    binary = "/tmp/analyze_graph_submission"
    nodes_path = "/home/user/nodes.csv"
    edges_path = "/home/user/edges.csv"
    matches_path = "/home/user/matches.json"

    with open(nodes_path, "rb") as f:
        original_nodes = f.read()
    with open(edges_path, "rb") as f:
        original_edges = f.read()
    original_matches = None
    if os.path.exists(matches_path):
        with open(matches_path, "rb") as f:
            original_matches = f.read()

    build = subprocess.run(["go", "build", "-o", binary, source], cwd="/home/user", capture_output=True, text=True, timeout=30)
    assert build.returncode == 0, f"analyze_graph.go does not compile: {build.stderr or build.stdout}"

    cases = [
        (
            [
                {"id": "p3", "type": "Person", "name": "Zoe"},
                {"id": "c1", "type": "Company", "name": "NovaWorks"},
                {"id": "i1", "type": "Industry", "name": "AI"},
                {"id": "p1", "type": "Person", "name": "Amy"},
                {"id": "p2", "type": "Person", "name": "Mona"},
                {"id": "c2", "type": "Company", "name": "LedgerCo"},
                {"id": "i2", "type": "Industry", "name": "ai"},
                {"id": "x1", "type": "Company", "name": "AI"},
            ],
            [
                {"source": "p3", "target": "c1", "relation": "WORKS_FOR"},
                {"source": "p1", "target": "c1", "relation": "WORKS_FOR"},
                {"source": "p2", "target": "c2", "relation": "WORKS_FOR"},
                {"source": "c1", "target": "i1", "relation": "OPERATES_IN"},
                {"source": "c2", "target": "i2", "relation": "OPERATES_IN"},
                {"source": "c2", "target": "x1", "relation": "OPERATES_IN"},
                {"source": "i1", "target": "c1", "relation": "OPERATES_IN"},
                {"source": "p2", "target": "c1", "relation": "INVESTS_IN"},
            ],
        ),
        (
            [
                {"id": "u1", "type": "Person", "name": "Derek"},
                {"id": "u2", "type": "Person", "name": "Bea"},
                {"id": "co1", "type": "Company", "name": "Orbit"},
                {"id": "co2", "type": "Company", "name": "Harbor"},
                {"id": "ind1", "type": "Industry", "name": "AI"},
                {"id": "ind2", "type": "Industry", "name": "Finance"},
            ],
            [
                {"source": "u1", "target": "co1", "relation": "WORKS_FOR"},
                {"source": "u2", "target": "co2", "relation": "WORKS_FOR"},
                {"source": "co1", "target": "ind1", "relation": "OPERATES_IN"},
                {"source": "co2", "target": "ind2", "relation": "OPERATES_IN"},
            ],
        ),
    ]

    try:
        for nodes, edges in cases:
            run_case(binary, nodes, edges)
    finally:
        with open(nodes_path, "wb") as f:
            f.write(original_nodes)
        with open(edges_path, "wb") as f:
            f.write(original_edges)
        if original_matches is None:
            if os.path.exists(matches_path):
                os.remove(matches_path)
        else:
            with open(matches_path, "wb") as f:
                f.write(original_matches)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
