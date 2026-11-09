#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest
from pymongo import MongoClient

SCRIPT_PATH = "/home/user/analyze_graph.py"
OUTPUT_PATH = "/home/user/influence_metrics.json"
PAPERS_PATH = "/home/user/raw_data/papers.json"
AUTHORS_PATH = "/home/user/raw_data/authors.json"


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT_PATH} does not contain valid JSON.")


def contains_key(value, key):
    if isinstance(value, dict):
        return key in value or any(contains_key(v, key) for v in value.values())
    if isinstance(value, list):
        return any(contains_key(v, key) for v in value)
    return False


def test_submission_and_original_output():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "rb") as f:
        source = f.read()
    assert source.strip(), "The analysis script is empty."
    compile(source, SCRIPT_PATH, "exec")

    data = load_output()
    assert "seed_paper" in data, "The key 'seed_paper' is missing from the output JSON."
    assert data["seed_paper"] == "P001", f"Expected 'seed_paper' to be 'P001', but got {data['seed_paper']}."
    assert "author_name" in data, "The key 'author_name' is missing from the output JSON."
    assert data["author_name"] == "Dr. Alice", f"Expected 'author_name' to be 'Dr. Alice', but got {data['author_name']}."
    assert "total_citing_papers" in data, "The key 'total_citing_papers' is missing from the output JSON."
    assert data["total_citing_papers"] == 4, f"Expected 'total_citing_papers' to be 4, but got {data['total_citing_papers']}."
    assert "total_influence_score" in data, "The key 'total_influence_score' is missing from the output JSON."
    assert float(data["total_influence_score"]) == 11.0, f"Expected 'total_influence_score' to be 11.0, but got {data['total_influence_score']}."


def test_script_executes_one_real_database_pipeline_on_changed_data():
    client = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=3000)
    client.admin.command("ping")
    db = client["research_db"]

    nonce = secrets.token_hex(5)
    author_name = f"Dynamic Author {nonce}"
    impacts = [
        1.0 + secrets.randbelow(20) / 10.0,
        3.1 + secrets.randbelow(20) / 10.0,
        5.1 + secrets.randbelow(20) / 10.0,
        7.1 + secrets.randbelow(20) / 10.0,
        9.1 + secrets.randbelow(20) / 10.0,
    ]
    expected_score = sum(impacts)

    papers = [
        {"paper_id": "P001", "title": f"Seed {nonce}", "impact_factor": 99.0, "cites": [], "author_id": "A1"},
        {"paper_id": "P101", "title": "Direct one", "impact_factor": impacts[0], "cites": ["P001"], "author_id": "A2"},
        {"paper_id": "P102", "title": "Direct two", "impact_factor": impacts[1], "cites": ["P001"], "author_id": "A2"},
        {"paper_id": "P103", "title": "Converging path", "impact_factor": impacts[2], "cites": ["P101", "P102"], "author_id": "A3"},
        {"paper_id": "P104", "title": "Depth two", "impact_factor": impacts[3], "cites": ["P103"], "author_id": "A4"},
        {"paper_id": "P105", "title": "Depth three", "impact_factor": impacts[4], "cites": ["P104"], "author_id": "A5"},
        {"paper_id": "P106", "title": "Too deep", "impact_factor": 5000.0, "cites": ["P105"], "author_id": "A5"},
        {"paper_id": "P999", "title": "Unrelated", "impact_factor": 7000.0, "cites": [], "author_id": "A1"},
    ]
    authors = [
        {"author_id": "A1", "name": author_name, "institution": "Dynamic Institute"},
        {"author_id": "A2", "name": "Other 2", "institution": "I2"},
        {"author_id": "A3", "name": "Other 3", "institution": "I3"},
        {"author_id": "A4", "name": "Other 4", "institution": "I4"},
        {"author_id": "A5", "name": "Other 5", "institution": "I5"},
    ]

    with open(PAPERS_PATH, "rb") as f:
        old_papers = f.read()
    with open(AUTHORS_PATH, "rb") as f:
        old_authors = f.read()

    db.command("profile", 0)
    db["system.profile"].drop()
    db.papers.delete_many({})
    db.authors.delete_many({})
    db.papers.insert_many(papers)
    db.authors.insert_many(authors)

    with open(PAPERS_PATH, "w") as f:
        json.dump(papers, f)
    with open(AUTHORS_PATH, "w") as f:
        json.dump(authors, f)

    db.command("profile", 2)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
        )
    finally:
        try:
            db.command("profile", 0)
        finally:
            with open(PAPERS_PATH, "wb") as f:
                f.write(old_papers)
            with open(AUTHORS_PATH, "wb") as f:
                f.write(old_authors)

    assert result.returncode == 0, f"analyze_graph.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    aggregate_entries = list(db["system.profile"].find({
        "op": "command",
        "command.aggregate": "papers",
    }))
    assert len(aggregate_entries) == 1, f"Expected exactly one aggregation on papers, observed {len(aggregate_entries)}."

    pipeline = aggregate_entries[0].get("command", {}).get("pipeline")
    assert isinstance(pipeline, list) and pipeline, "The recorded aggregate command has no pipeline."

    first_match = pipeline[0].get("$match") if isinstance(pipeline[0], dict) else None
    assert isinstance(first_match, dict), "The pipeline must start with a $match stage."
    paper_match = first_match.get("paper_id")
    assert paper_match == "P001" or paper_match == {"$eq": "P001"}, "The first stage must match paper_id P001."

    graph_stages = [stage["$graphLookup"] for stage in pipeline if isinstance(stage, dict) and "$graphLookup" in stage]
    assert len(graph_stages) == 1, "The pipeline must contain exactly one $graphLookup stage."
    graph = graph_stages[0]
    assert graph.get("from") == "papers", "$graphLookup must traverse the papers collection."
    assert graph.get("connectFromField") == "paper_id", "$graphLookup must recurse from paper_id."
    assert graph.get("connectToField") == "cites", "$graphLookup must follow reverse citations through cites."
    assert graph.get("maxDepth") == 3, "$graphLookup must use maxDepth 3."
    graph_alias = graph.get("as")
    assert isinstance(graph_alias, str) and graph_alias, "$graphLookup must store its results in an array."

    lookup_stages = [stage["$lookup"] for stage in pipeline if isinstance(stage, dict) and "$lookup" in stage]
    assert lookup_stages, "The pipeline must contain a $lookup stage."
    assert any(stage.get("from") == "authors" for stage in lookup_stages), "$lookup must query the authors collection."

    graph_index = next(i for i, stage in enumerate(pipeline) if isinstance(stage, dict) and "$graphLookup" in stage)
    later_stages = pipeline[graph_index + 1:]
    assert contains_key(later_stages, "total_citing_papers"), "The pipeline must calculate total_citing_papers after $graphLookup."
    assert contains_key(later_stages, "total_influence_score"), "The pipeline must calculate total_influence_score after $graphLookup."
    assert contains_key(later_stages, "$sum"), "The influence score must be summed inside the aggregation pipeline."

    project_stages = [stage["$project"] for stage in pipeline if isinstance(stage, dict) and "$project" in stage]
    assert project_stages, "The pipeline must project the requested final fields."
    assert any(all(key in project for key in ("seed_paper", "author_name", "total_citing_papers", "total_influence_score")) for project in project_stages), "A $project stage must define all four requested output fields."

    data = load_output()
    assert isinstance(data, dict), "The output must be one JSON object."
    assert set(data) == {"seed_paper", "author_name", "total_citing_papers", "total_influence_score"}, "The output JSON must contain exactly the requested fields."
    assert data["seed_paper"] == "P001"
    assert data["author_name"] == author_name
    assert data["total_citing_papers"] == 5, "The graph traversal must count each reachable paper once and exclude depth 4."
    assert abs(float(data["total_influence_score"]) - expected_score) < 1e-8
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
