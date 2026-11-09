#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/traced_graph_runner.py
import json
import runpy
import sys

script_path = sys.argv[1]
trace_path = sys.argv[2]
trace = {
    "queries": [],
    "centrality_calls": []
}

def profiler(frame, event, arg):
    if event != "call":
        return
    module = frame.f_globals.get("__name__", "")
    name = frame.f_code.co_name

    if module == "rdflib.graph" and name == "query":
        graph = frame.f_locals.get("self")
        query = frame.f_locals.get("query_object", frame.f_locals.get("query", ""))
        edges = []
        if graph is not None:
            try:
                for source, predicate, target in graph:
                    if str(predicate) == "http://example.org/fraud/transferredTo":
                        edges.append([str(source), str(target)])
            except Exception:
                pass
        trace["queries"].append({
            "query": str(query),
            "transferred_edges": edges
        })

    if module.startswith("networkx.") and name == "degree_centrality":
        graph = frame.f_locals.get("G")
        if graph is not None:
            try:
                trace["centrality_calls"].append({
                    "nodes": [str(node) for node in graph.nodes()],
                    "edges": [[str(source), str(target)] for source, target in graph.edges()]
                })
            except Exception:
                pass

sys.argv = [script_path]
try:
    sys.setprofile(profiler)
    runpy.run_path(script_path, run_name="__main__")
finally:
    sys.setprofile(None)
    with open(trace_path, "w") as trace_file:
        json.dump(trace, trace_file)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

SCRIPT = "/home/user/analyze_graph.py"
CSV_PATH = "/home/user/transactions.csv"
REPORT_PATH = "/home/user/fraud_report.json"
NS = "http://example.org/fraud/"
PREDICATE = NS + "transferredTo"


def run(command):
    result = subprocess.run(
        command,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Analysis script failed with exit code {result.returncode}:\n{result.stdout}"
    )


def load_and_check_report(expected_participants, expected_mastermind):
    assert os.path.exists(REPORT_PATH), f"The output file {REPORT_PATH} was not found."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a file."

    with open(REPORT_PATH, "r") as report_file:
        try:
            data = json.load(report_file)
        except json.JSONDecodeError as error:
            raise AssertionError(f"The file {REPORT_PATH} does not contain valid JSON.") from error

    assert "ring_participants" in data, "The JSON output is missing the 'ring_participants' key."
    assert "mastermind" in data, "The JSON output is missing the 'mastermind' key."

    actual_participants = data["ring_participants"]
    assert isinstance(actual_participants, list), "'ring_participants' must be a list."
    assert sorted(actual_participants) == sorted(expected_participants), (
        f"Expected ring_participants to be {expected_participants}, but got {actual_participants}."
    )
    assert actual_participants == sorted(actual_participants), (
        "'ring_participants' list is not sorted alphabetically."
    )

    actual_mastermind = data["mastermind"]
    assert actual_mastermind == expected_mastermind, (
        f"Expected mastermind to be '{expected_mastermind}', but got '{actual_mastermind}'."
    )


def derive_expected(account_edges):
    edges = set(account_edges)
    nodes = {node for edge in edges for node in edge}
    participants = set()

    for a in nodes:
        for b in nodes:
            if a == b or (a, b) not in edges:
                continue
            for c in nodes:
                if c == a or c == b:
                    continue
                if (b, c) in edges and (c, a) in edges:
                    participants.update((a, b, c))

    participant_uris = sorted(NS + account for account in participants)
    assert participant_uris, "Verifier-generated graph unexpectedly has no 3-hop ring."

    degrees = {}
    for account in participants:
        degree = sum(
            1
            for source, target in edges
            if source in participants and target in participants
            and (source == account or target == account)
        )
        degrees[NS + account] = degree

    highest = max(degrees.values())
    mastermind = min(uri for uri, degree in degrees.items() if degree == highest)
    return participant_uris, mastermind


def write_csv(account_edges):
    with open(CSV_PATH, "w", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["tx_id", "source_acc", "target_acc", "amount", "timestamp"])
        for index, (source, target) in enumerate(account_edges, 1):
            writer.writerow([
                f"DYN_{index}", source, target, 100 + index,
                f"2026-01-01T00:{index:02d}:00Z"
            ])


def run_dynamic_case(account_edges, case_number):
    write_csv(account_edges)
    expected_participants, expected_mastermind = derive_expected(account_edges)
    trace_path = f"/tmp/graph_trace_{case_number}.json"
    run(["python3", "/tmp/traced_graph_runner.py", SCRIPT, trace_path])
    load_and_check_report(expected_participants, expected_mastermind)

    with open(trace_path, "r") as trace_file:
        trace = json.load(trace_file)

    expected_full_edges = {
        (NS + source, NS + target) for source, target in account_edges
    }
    assert trace["queries"], "The script did not execute an rdflib Graph.query SPARQL query."
    assert any(
        set(map(tuple, query_call["transferred_edges"])) == expected_full_edges
        for query_call in trace["queries"]
    ), "The SPARQL query was not executed on the required RDF transferredTo graph."

    participant_set = set(expected_participants)
    expected_subgraph_edges = {
        (source, target)
        for source, target in expected_full_edges
        if source in participant_set and target in participant_set
    }
    assert trace["centrality_calls"], (
        "The script did not call networkx.degree_centrality."
    )
    assert any(
        set(call["nodes"]) == participant_set
        and set(map(tuple, call["edges"])) == expected_subgraph_edges
        for call in trace["centrality_calls"]
    ), "Degree centrality was not computed on the isolated ring-participant subgraph."


def test_script_executes_and_performs_required_analysis():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} was not found."
    assert os.path.isfile(SCRIPT), f"The path {SCRIPT} is not a file."

    with open(CSV_PATH, "rb") as original_file:
        original_csv = original_file.read()

    try:
        # Preserve the original verifier's assertions, but first generate the report
        # by actually executing the submitted artifact.
        run(["python3", SCRIPT])
        expected_participants = [
            "http://example.org/fraud/ACC_001",
            "http://example.org/fraud/ACC_002",
            "http://example.org/fraud/ACC_003",
            "http://example.org/fraud/ACC_004",
            "http://example.org/fraud/ACC_005",
        ]
        load_and_check_report(
            expected_participants,
            "http://example.org/fraud/ACC_001",
        )

        token = secrets.token_hex(4).upper()
        names = [f"ACC_{token}_{index}" for index in range(1, 13)]

        # Two triangles sharing one coordinator, plus a non-qualifying 4-cycle.
        case_one = [
            (names[0], names[1]), (names[1], names[2]), (names[2], names[0]),
            (names[0], names[3]), (names[3], names[4]), (names[4], names[0]),
            (names[3], names[5]), (names[5], names[6]),
            (names[6], names[7]), (names[7], names[3]),
            (names[8], names[9]),
        ]
        run_dynamic_case(case_one, 1)

        # A single triangle tests the specified alphabetical tie break.
        case_two = [
            (names[9], names[11]), (names[11], names[10]), (names[10], names[9]),
            (names[0], names[1]), (names[1], names[2]),
            (names[2], names[3]), (names[3], names[0]),
        ]
        run_dynamic_case(case_two, 2)
    finally:
        with open(CSV_PATH, "wb") as original_file:
            original_file.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
