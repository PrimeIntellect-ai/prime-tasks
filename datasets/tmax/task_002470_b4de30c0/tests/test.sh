#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import runpy
import sys
import uuid
from pathlib import Path

import pytest

VENDOR_ROOT = Path("/app/pygraph_etl-1.2.0")
MAPPER_PATH = VENDOR_ROOT / "pygraph_etl" / "mapper.py"
SCRIPT_PATH = Path("/home/user/build_graph.py")
DATA_PATH = Path("/home/user/data/entities.jsonl")
CSV_PATH = Path("/home/user/projected_edges.csv")


def read_edges(path):
    edges = set()
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, "CSV is missing a header row."
        assert "source_id" in reader.fieldnames, "Missing 'source_id' column in CSV header."
        assert "target_id" in reader.fieldnames, "Missing 'target_id' column in CSV header."
        assert "edge_type" in reader.fieldnames, "Missing 'edge_type' column in CSV header."
        assert reader.fieldnames == ["source_id", "target_id", "edge_type"], (
            "CSV must have exactly the columns source_id, target_id, and edge_type."
        )
        for row in reader:
            edges.add((str(row["source_id"]), str(row["target_id"]), str(row["edge_type"])))
    return edges


def derive_edges(documents):
    expected = set()
    for doc in documents:
        company_id = str(doc.get("id", ""))
        for emp in doc.get("employees", []):
            emp_id = str(emp.get("id", ""))
            if company_id and emp_id:
                expected.add((company_id, emp_id, "EMPLOYS"))
            for proj in emp.get("projects", []):
                proj_id = str(proj)
                if emp_id and proj_id:
                    expected.add((emp_id, proj_id, "WORKS_ON"))
    return expected


def execute_script():
    if CSV_PATH.exists():
        CSV_PATH.unlink()
    old_argv = sys.argv[:]
    old_cwd = os.getcwd()
    try:
        sys.argv = [str(SCRIPT_PATH)]
        os.chdir(str(SCRIPT_PATH.parent))
        try:
            runpy.run_path(str(SCRIPT_PATH), run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"build_graph.py exited with status {exc.code}"
    finally:
        sys.argv = old_argv
        os.chdir(old_cwd)
    assert CSV_PATH.exists(), f"Agent output file not found at {CSV_PATH}"


def test_fixed_package_and_pipeline_execution():
    assert MAPPER_PATH.is_file(), f"Vendored mapper not found at {MAPPER_PATH}"
    assert SCRIPT_PATH.is_file(), f"Pipeline script not found at {SCRIPT_PATH}"
    assert DATA_PATH.is_file(), f"Data file not found at {DATA_PATH}"

    sys.path.insert(0, str(VENDOR_ROOT))
    for name in list(sys.modules):
        if name == "pygraph_etl" or name.startswith("pygraph_etl."):
            del sys.modules[name]

    from pygraph_etl import GraphProjector

    schema = {
        "Company": {
            "employees": {
                "type": "has_many",
                "edge_type": "EMPLOYS",
                "nested": {
                    "projects": {"type": "has_many", "edge_type": "WORKS_ON"}
                },
            }
        }
    }
    package_docs = [{
        "type": "Company",
        "id": "package-company",
        "employees": [
            {"id": "package-e1", "projects": ["package-p1", "package-p2"]},
            {"id": "package-e2", "projects": ["package-p3"]},
            {"id": "package-e3", "projects": ["package-p4"]},
        ],
    }]
    package_expected = derive_edges(package_docs)
    package_actual = set(GraphProjector(schema).materialize(package_docs))
    assert package_actual == package_expected, (
        "The vendored GraphProjector still fails to expand every has_many item."
    )

    original_materialize = GraphProjector.materialize
    materialize_calls = []

    def tracked_materialize(self, data):
        materialize_calls.append(data)
        return original_materialize(self, data)

    GraphProjector.materialize = tracked_materialize

    token = uuid.uuid4().hex
    synthetic_docs = [
        {
            "type": "Company",
            "id": f"C-{token}-1",
            "employees": [
                {"id": f"E-{token}-1", "projects": [f"P-{token}-1", f"P-{token}-2"]},
                {"id": f"E-{token}-2", "projects": [f"P-{token}-2", f"P-{token}-3"]},
                {"id": f"E-{token}-3", "projects": [f"P-{token}-4"]},
            ],
        },
        {
            "type": "Company",
            "id": f"C-{token}-2",
            "employees": [
                {"id": f"E-{token}-4", "projects": [f"P-{token}-5"]},
                {"id": f"E-{token}-5", "projects": [f"P-{token}-6", f"P-{token}-7"]},
            ],
        },
    ]
    original_data = DATA_PATH.read_bytes()
    try:
        with open(DATA_PATH, "w", encoding="utf-8") as f:
            for doc in synthetic_docs:
                f.write(json.dumps(doc) + "\n")
        execute_script()
        assert materialize_calls, "build_graph.py did not use GraphProjector.materialize()."
        assert read_edges(CSV_PATH) == derive_edges(synthetic_docs), (
            "build_graph.py did not correctly project a fresh, dynamically generated dataset."
        )
    finally:
        DATA_PATH.write_bytes(original_data)
        GraphProjector.materialize = original_materialize

    execute_script()


def test_jaccard_similarity_of_edges():
    agent_csv_path = "/home/user/projected_edges.csv"
    data_path = "/home/user/data/entities.jsonl"

    assert os.path.exists(agent_csv_path), f"Agent output file not found at {agent_csv_path}"
    assert os.path.exists(data_path), f"Data file not found at {data_path}"

    expected_edges = set()
    with open(data_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            doc = json.loads(line)
            company_id = str(doc.get("id", ""))
            employees = doc.get("employees", [])
            for emp in employees:
                emp_id = str(emp.get("id", ""))
                if company_id and emp_id:
                    expected_edges.add((company_id, emp_id, "EMPLOYS"))
                projects = emp.get("projects", [])
                for proj in projects:
                    proj_id = str(proj)
                    if emp_id and proj_id:
                        expected_edges.add((emp_id, proj_id, "WORKS_ON"))

    assert len(expected_edges) > 0, "Failed to parse expected edges from source data."
    agent_edges = read_edges(agent_csv_path)
    intersection = agent_edges.intersection(expected_edges)
    union = agent_edges.union(expected_edges)
    jaccard = len(intersection) / len(union) if len(union) > 0 else 0.0

    assert jaccard >= 0.99, (
        f"Jaccard similarity {jaccard:.4f} is below threshold 0.99. "
        f"Agent produced {len(agent_edges)} edges, expected {len(expected_edges)} edges. "
        f"Intersection: {len(intersection)}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
