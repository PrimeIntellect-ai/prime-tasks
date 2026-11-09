#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid

import pytest
from pymongo import MongoClient
from neo4j import GraphDatabase

SCRIPT_PATH = "/home/user/validate_submission.py"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Missing classifier script: {SCRIPT_PATH}"


def run_classifier(file_path):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, file_path],
            capture_output=True,
            text=True,
            timeout=8
        )
        if result.returncode != 0:
            return f"EXIT {result.returncode}: {result.stdout.strip()}"
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"


def assert_classification(file_path, expected):
    output = run_classifier(file_path)
    assert output == expected, f"Expected {expected}, got {output!r} for {file_path}"


def write_json(directory, name, contents):
    path = os.path.join(directory, name)
    import json
    with open(path, "w", encoding="utf-8") as f:
        json.dump(contents, f)
    return path


@pytest.fixture(scope="session")
def live_services():
    mongo = MongoClient("mongodb://localhost:27017/", serverSelectionTimeoutMS=3000)
    mongo.admin.command("ping")
    db = mongo.biomed

    # Restore the documented corpus state deterministically.
    db.authors.delete_many({"author_id": {"$in": ["alice", "bob"]}})
    db.authors.insert_many([
        {"author_id": "alice", "trust_score": 0.9},
        {"author_id": "bob", "trust_score": 0.2},
    ])

    neo = GraphDatabase.driver("bolt://localhost:7687", auth=None)
    neo.verify_connectivity()
    with neo.session(database="neo4j") as session:
        session.run(
            "MERGE (p1:Paper {paper_id:'P001'}) "
            "MERGE (p2:Paper {paper_id:'P002'}) "
            "MERGE (p3:Paper {paper_id:'EVIL_TARGET'}) "
            "MERGE (p2)-[:CITES]->(p3)"
        ).consume()

    yield db, neo
    neo.close()
    mongo.close()


def test_clean_corpus(live_services):
    assert os.path.isdir(CLEAN_DIR), f"Missing clean corpus directory: {CLEAN_DIR}"
    clean_files = sorted([f for f in os.listdir(CLEAN_DIR) if f.endswith('.json')])
    assert len(clean_files) > 0, "No JSON files found in clean corpus"

    failed_files = []
    for f in clean_files:
        file_path = os.path.join(CLEAN_DIR, f)
        output = run_classifier(file_path)
        if output != "ACCEPT":
            failed_files.append((f, output))

    if failed_files:
        msg = f"{len(failed_files)} of {len(clean_files)} clean modified (rejected or errored).\nOffending files:\n"
        for f, out in failed_files:
            msg += f"  {f} (output: {out})\n"
        pytest.fail(msg)


def test_evil_corpus(live_services):
    assert os.path.isdir(EVIL_DIR), f"Missing evil corpus directory: {EVIL_DIR}"
    evil_files = sorted([f for f in os.listdir(EVIL_DIR) if f.endswith('.json')])
    assert len(evil_files) > 0, "No JSON files found in evil corpus"

    failed_files = []
    for f in evil_files:
        file_path = os.path.join(EVIL_DIR, f)
        output = run_classifier(file_path)
        if output != "REJECT":
            failed_files.append((f, output))

    if failed_files:
        msg = f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted or errored).\nOffending files:\n"
        for f, out in failed_files:
            msg += f"  {f} (output: {out})\n"
        pytest.fail(msg)


def test_dynamic_mongodb_aggregation_and_author_validation(live_services):
    db, neo = live_services
    token = uuid.uuid4().hex
    author = "author_" + token
    paper = "paper_" + token
    target = "target_" + token

    db.authors.delete_many({"author_id": author})
    db.authors.insert_many([
        {"author_id": author, "trust_score": 0.2},
        {"author_id": author, "trust_score": 0.9},
    ])
    with neo.session(database="neo4j") as session:
        session.run("MERGE (:Paper {paper_id:$target})", target=target).consume()

    # Profiling verifies that the classifier issues an actual MongoDB aggregation.
    db.command("profile", 2)
    before = db.system.profile.count_documents({"command.aggregate": "authors"})

    with tempfile.TemporaryDirectory(prefix="submission_" + token + "_") as td:
        path = write_json(td, uuid.uuid4().hex + ".json", {
            "paper_id": paper,
            "author_id": author,
            "cites": [target],
        })
        assert_classification(path, "ACCEPT")
        after = db.system.profile.count_documents({"command.aggregate": "authors"})
        assert after > before, "Classifier did not aggregate the MongoDB authors collection"

        # Identical input must change classification when the live trust records change.
        db.authors.update_many({"author_id": author}, {"$set": {"trust_score": 0.1}})
        assert_classification(path, "REJECT")

        malformed = write_json(td, uuid.uuid4().hex + ".json", {
            "paper_id": paper + "_malformed",
            "author_id": {"$ne": None},
            "cites": [target],
        })
        assert_classification(malformed, "REJECT")


def test_dynamic_neo4j_existence_and_cycle_checks(live_services):
    db, neo = live_services
    token = uuid.uuid4().hex
    author = "graph_author_" + token
    db.authors.delete_many({"author_id": author})
    db.authors.insert_one({"author_id": author, "trust_score": 0.95})

    paper_exists = "new_exists_" + token
    target_exists = "existing_" + token
    paper_cycle = "new_cycle_" + token
    target_cycle = "cycle_target_" + token

    with neo.session(database="neo4j") as session:
        session.run(
            "MERGE (:Paper {paper_id:$a}) "
            "MERGE (:Paper {paper_id:$b}) "
            "MERGE (:Paper {paper_id:$c})",
            a=target_exists, b=target_cycle, c=paper_cycle
        ).consume()

    with tempfile.TemporaryDirectory(prefix="graph_submission_" + token + "_") as td:
        existence_path = write_json(td, uuid.uuid4().hex + ".json", {
            "paper_id": paper_exists,
            "author_id": author,
            "cites": [target_exists],
        })
        assert_classification(existence_path, "ACCEPT")

        # The same JSON must be rejected after its citation target is removed.
        with neo.session(database="neo4j") as session:
            session.run(
                "MATCH (p:Paper {paper_id:$id}) DETACH DELETE p",
                id=target_exists
            ).consume()
        assert_classification(existence_path, "REJECT")

        cycle_path = write_json(td, uuid.uuid4().hex + ".json", {
            "paper_id": paper_cycle,
            "author_id": author,
            "cites": [target_cycle],
        })
        assert_classification(cycle_path, "ACCEPT")

        # Add the reverse citation; the identical submission would now form a 2-cycle.
        with neo.session(database="neo4j") as session:
            session.run(
                "MATCH (target:Paper {paper_id:$target}), (paper:Paper {paper_id:$paper}) "
                "MERGE (target)-[:CITES]->(paper)",
                target=target_cycle, paper=paper_cycle
            ).consume()
        assert_classification(cycle_path, "REJECT")


def test_dynamic_missing_fields(live_services):
    db, neo = live_services
    token = uuid.uuid4().hex
    author = "missing_author_" + token
    target = "missing_target_" + token
    db.authors.insert_one({"author_id": author, "trust_score": 0.9})
    with neo.session(database="neo4j") as session:
        session.run("MERGE (:Paper {paper_id:$id})", id=target).consume()

    cases = [
        {"author_id": author, "cites": [target]},
        {"paper_id": "missing_author_paper_" + token, "cites": [target]},
        {"paper_id": "missing_cites_paper_" + token, "author_id": author},
    ]
    with tempfile.TemporaryDirectory(prefix="missing_fields_" + token + "_") as td:
        for value in cases:
            path = write_json(td, uuid.uuid4().hex + ".json", value)
            assert_classification(path, "REJECT")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
