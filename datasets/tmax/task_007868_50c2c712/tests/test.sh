#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/build_graph.sh"
DATASET_DIR = "/home/user/datasets"
LOG_PATH = "/home/user/deadlock_citations.log"
CYPHER_PATH = "/home/user/init.cypher"


def run_script_fresh():
    for path in (LOG_PATH, CYPHER_PATH):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=30,
    )


@pytest.fixture(scope="module", autouse=True)
def execute_original_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    run_script_fresh()


def test_script_exists_and_executable():
    script_path = "/home/user/build_graph.sh"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_deadlock_citations_log():
    log_path = "/home/user/deadlock_citations.log"
    assert os.path.isfile(log_path), f"The file {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "PUB1<->PUB2",
        "PUB3<->PUB4"
    ]

    assert content == expected, f"Content of {log_path} does not match the expected deadlocks."


def test_init_cypher_script():
    cypher_path = "/home/user/init.cypher"
    assert os.path.isfile(cypher_path), f"The file {cypher_path} is missing."

    with open(cypher_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "CREATE (:Project {id: 'P1', title: 'AI Research'});",
        "CREATE (:Project {id: 'P2', title: 'DB Systems'});",
        "CREATE (:Publication {id: 'PUB1', citation_count: 2});",
        "CREATE (:Publication {id: 'PUB2', citation_count: 1});",
        "CREATE (:Publication {id: 'PUB3', citation_count: 2});",
        "CREATE (:Publication {id: 'PUB4', citation_count: 2});",
        "CREATE (:Researcher {id: 'R1', name: 'Alice'});",
        "CREATE (:Researcher {id: 'R2', name: 'Bob'});",
        "CREATE (:Researcher {id: 'R3', name: 'Charlie'});",
        "CREATE (P1)-[:PRODUCED]->(PUB1);",
        "CREATE (P1)-[:PRODUCED]->(PUB2);",
        "CREATE (P2)-[:PRODUCED]->(PUB3);",
        "CREATE (P2)-[:PRODUCED]->(PUB4);",
        "CREATE (PUB1)-[:CITES]->(PUB2);",
        "CREATE (PUB1)-[:CITES]->(PUB3);",
        "CREATE (PUB2)-[:CITES]->(PUB1);",
        "CREATE (PUB2)-[:CITES]->(PUB4);",
        "CREATE (PUB3)-[:CITES]->(PUB4);",
        "CREATE (PUB4)-[:CITES]->(PUB1);",
        "CREATE (PUB4)-[:CITES]->(PUB3);",
        "CREATE (R1)-[:WORKS_ON]->(P1);",
        "CREATE (R2)-[:WORKS_ON]->(P2);",
        "CREATE (R3)-[:WORKS_ON]->(P1);"
    ]

    assert content == sorted(expected), f"Content of {cypher_path} does not match the expected Cypher statements."


def test_z_pipeline_processes_changed_inputs():
    suffix = secrets.token_hex(4).upper()
    project_ids = [f"Q{suffix}A", f"Q{suffix}B"]
    pub_ids = [f"DOC{suffix}{letter}" for letter in "ABCDE"]
    researcher_ids = [f"RES{suffix}{n}" for n in range(1, 4)]

    researchers = [
        {"researcher_id": researcher_ids[0], "name": f"Ada{suffix}", "project_id": project_ids[0]},
        {"researcher_id": researcher_ids[1], "name": f"Ben{suffix}", "project_id": project_ids[1]},
        {"researcher_id": researcher_ids[2], "name": f"Cy{suffix}", "project_id": project_ids[0]},
    ]
    projects = [
        {"project_id": project_ids[0], "title": f"Graph Study {suffix}", "publications": pub_ids[:3]},
        {"project_id": project_ids[1], "title": f"Data Study {suffix}", "publications": pub_ids[3:]},
    ]
    citations = [
        (pub_ids[0], pub_ids[1]),
        (pub_ids[1], pub_ids[0]),
        (pub_ids[2], pub_ids[3]),
        (pub_ids[3], pub_ids[2]),
        (pub_ids[0], pub_ids[2]),
        (pub_ids[4], pub_ids[0]),
        (pub_ids[1], pub_ids[3]),
        (pub_ids[3], pub_ids[4]),
    ]

    with open(os.path.join(DATASET_DIR, "researchers.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["researcher_id", "name", "project_id"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(researchers)

    with open(os.path.join(DATASET_DIR, "projects.json"), "w") as f:
        json.dump(projects, f)

    with open(os.path.join(DATASET_DIR, "citations.csv"), "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["citing_pub_id", "cited_pub_id"])
        writer.writerows(citations)

    citation_set = set(citations)
    expected_deadlocks = sorted({
        f"{min(left, right)}<->{max(left, right)}"
        for left, right in citations
        if left != right and (right, left) in citation_set
    })

    counts = collections.Counter(cited for _, cited in citations)
    expected_cypher = []
    for project in projects:
        expected_cypher.append(
            f"CREATE (:Project {{id: '{project['project_id']}', title: '{project['title']}'}});"
        )
        for pub_id in project["publications"]:
            expected_cypher.append(
                f"CREATE (:Publication {{id: '{pub_id}', citation_count: {counts[pub_id]}}});"
            )
            expected_cypher.append(
                f"CREATE ({project['project_id']})-[:PRODUCED]->({pub_id});"
            )
    for researcher in researchers:
        expected_cypher.append(
            f"CREATE (:Researcher {{id: '{researcher['researcher_id']}', name: '{researcher['name']}'}});"
        )
        expected_cypher.append(
            f"CREATE ({researcher['researcher_id']})-[:WORKS_ON]->({researcher['project_id']});"
        )
    for citing, cited in citations:
        expected_cypher.append(f"CREATE ({citing})-[:CITES]->({cited});")
    expected_cypher.sort()

    run_script_fresh()

    assert os.path.isfile(LOG_PATH), f"The file {LOG_PATH} is missing after executing the script."
    assert os.path.isfile(CYPHER_PATH), f"The file {CYPHER_PATH} is missing after executing the script."

    with open(LOG_PATH) as f:
        actual_deadlocks = f.read().strip().splitlines()
    with open(CYPHER_PATH) as f:
        actual_cypher = f.read().strip().splitlines()

    assert actual_deadlocks == expected_deadlocks
    assert actual_cypher == expected_cypher
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
