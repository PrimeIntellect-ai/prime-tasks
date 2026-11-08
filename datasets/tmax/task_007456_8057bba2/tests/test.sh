#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import uuid
import random
import subprocess
import tempfile
import pytest

STATEMENT = "MATCH path=(e:Entity {id: $entity_id})-[:TRANSFERRED*1..4]->(e) RETURN path"


def read_jsonl(path):
    objects = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    objects.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {path}: {line}")
    return objects


def test_00_requested_artifacts_execute_and_transform_dynamic_inputs():
    source_path = "/home/user/generate_queries.c"
    script_path = "/home/user/aggregate.sh"

    assert os.path.isfile(source_path), f"Required C source {source_path} is missing."
    assert os.path.isfile(script_path), f"Required bash script {script_path} is missing."

    with tempfile.TemporaryDirectory(prefix="verifier_") as tmpdir:
        executable = os.path.join(tmpdir, "generate_queries")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", executable],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"{source_path} did not compile successfully:\n{compile_result.stderr}"
        )

        dynamic_ids = [f"DYN_{uuid.uuid4().hex}" for _ in range(3)]
        dynamic_csv = os.path.join(tmpdir, f"input_{uuid.uuid4().hex}.csv")
        dynamic_jsonl = os.path.join(tmpdir, f"output_{uuid.uuid4().hex}.jsonl")
        with open(dynamic_csv, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["entity_id", "risk_score"])
            for index, entity_id in enumerate(dynamic_ids):
                writer.writerow([entity_id, 61 + index])

        run_result = subprocess.run(
            [executable, dynamic_csv, dynamic_jsonl],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert run_result.returncode == 0, (
            "The compiled C program failed when invoked with the required input and output arguments:\n"
            + run_result.stderr
        )
        assert os.path.isfile(dynamic_jsonl), "The compiled C program did not create its requested output path."
        expected_dynamic_queries = [
            {"statement": STATEMENT, "parameters": {"entity_id": entity_id}}
            for entity_id in dynamic_ids
        ]
        assert read_jsonl(dynamic_jsonl) == expected_dynamic_queries, (
            "The compiled C program did not transform a dynamic CSV fixture correctly."
        )

        canonical_run = subprocess.run(
            [executable, "/home/user/suspicious.csv", "/home/user/cypher_queries.jsonl"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert canonical_run.returncode == 0, (
            "The compiled C program failed on the required paths:\n" + canonical_run.stderr
        )

    graph_path = "/home/user/graph_results.jsonl"
    report_path = "/home/user/audit_report.json"
    with open(graph_path, "rb") as f:
        original_graph = f.read()

    dynamic_rows = [
        {"entity_id": f"AGG_{uuid.uuid4().hex}", "cycle_lengths": []},
        {"entity_id": f"AGG_{uuid.uuid4().hex}", "cycle_lengths": [random.randint(5, 30)]},
        {"entity_id": f"AGG_{uuid.uuid4().hex}", "cycle_lengths": [2, 17, 6, 17]},
    ]
    expected_dynamic_report = [
        {
            "entity_id": row["entity_id"],
            "total_cycles": len(row["cycle_lengths"]),
            "max_cycle_length": max(row["cycle_lengths"]) if row["cycle_lengths"] else None,
        }
        for row in dynamic_rows
    ]

    dynamic_error = None
    try:
        with open(graph_path, "w") as f:
            for row in dynamic_rows:
                f.write(json.dumps(row) + "\n")

        aggregate_run = subprocess.run(
            ["bash", "-x", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert aggregate_run.returncode == 0, (
            f"{script_path} failed on a dynamic graph-results fixture:\n{aggregate_run.stderr}"
        )
        assert re.search(r"^\++ (?:[^\s]*/)?jq(?:\s|$)", aggregate_run.stderr, re.MULTILINE), (
            f"{script_path} did not invoke jq while performing the aggregation."
        )
        assert os.path.isfile(report_path), f"{script_path} did not create {report_path}."
        with open(report_path, "r") as f:
            try:
                actual_dynamic_report = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"{script_path} produced invalid JSON for a dynamic input fixture.")
        assert actual_dynamic_report == expected_dynamic_report, (
            "The aggregation script did not transform a dynamic graph-results fixture correctly."
        )
    except BaseException as exc:
        dynamic_error = exc
    finally:
        with open(graph_path, "wb") as f:
            f.write(original_graph)
        canonical_aggregate = subprocess.run(
            ["bash", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )

    if dynamic_error is not None:
        raise dynamic_error
    assert canonical_aggregate.returncode == 0, (
        f"{script_path} failed on the required input path:\n{canonical_aggregate.stderr}"
    )


def test_cypher_queries_jsonl():
    csv_path = "/home/user/suspicious.csv"
    jsonl_path = "/home/user/cypher_queries.jsonl"

    assert os.path.isfile(jsonl_path), f"Output file {jsonl_path} is missing. Ensure your C program writes to this path."

    expected_objects = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            entity_id = row["entity_id"]
            expected_objects.append({
                "statement": "MATCH path=(e:Entity {id: $entity_id})-[:TRANSFERRED*1..4]->(e) RETURN path",
                "parameters": {"entity_id": entity_id}
            })

    actual_objects = []
    with open(jsonl_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual_objects.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {jsonl_path}: {line}")

    assert actual_objects == expected_objects, f"Contents of {jsonl_path} do not match the expected output based on the entities in {csv_path}."


def test_audit_report_json():
    input_jsonl = "/home/user/graph_results.jsonl"
    output_json = "/home/user/audit_report.json"

    assert os.path.isfile(output_json), f"Output file {output_json} is missing. Ensure your bash script writes to this path."

    expected_report = []
    with open(input_jsonl, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                data = json.loads(line)
                entity_id = data["entity_id"]
                cycle_lengths = data.get("cycle_lengths", [])
                total_cycles = len(cycle_lengths)
                max_cycle_length = max(cycle_lengths) if total_cycles > 0 else None

                expected_report.append({
                    "entity_id": entity_id,
                    "total_cycles": total_cycles,
                    "max_cycle_length": max_cycle_length
                })

    with open(output_json, "r") as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_json} does not contain valid JSON.")

    assert actual_report == expected_report, f"Contents of {output_json} do not match the expected aggregated report. Check your jq aggregation logic."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
