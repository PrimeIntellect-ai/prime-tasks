#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile
import uuid

EXECUTABLE = "/home/user/query_sanitizer"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
RESTRICTED = {404, 808, 909}


def test_executable_exists_and_is_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def run_sanitizer(filepath):
    result = subprocess.run(
        [EXECUTABLE, filepath],
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.stdout.strip()


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, f"No JSON files found in clean corpus {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No JSON files found in evil corpus {EVIL_CORPUS_DIR}"

    clean_failed = []
    for filepath in clean_files:
        output = run_sanitizer(filepath)
        if output != "ACCEPT":
            clean_failed.append((os.path.basename(filepath), output))

    evil_failed = []
    for filepath in evil_files:
        output = run_sanitizer(filepath)
        if output != "REJECT":
            evil_failed.append((os.path.basename(filepath), output))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: " + ", ".join(f"{f} (got {out})" for f, out in clean_failed))
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: " + ", ".join(f"{f} (got {out})" for f, out in evil_failed))

    assert not errors, "\n".join(errors)


def expected_result(pipeline):
    for stage in pipeline:
        if not isinstance(stage, dict):
            continue

        match = stage.get("$match")
        if isinstance(match, dict) and "user_id" in match:
            query = match["user_id"]
            if query in RESTRICTED if isinstance(query, int) else False:
                return "REJECT"
            if isinstance(query, dict):
                values = query.get("$in")
                if isinstance(values, list) and any(isinstance(v, int) and v in RESTRICTED for v in values):
                    return "REJECT"

        graph = stage.get("$graphLookup")
        if isinstance(graph, dict):
            start = graph.get("startWith")
            if isinstance(start, int) and start in RESTRICTED:
                return "REJECT"

        if "$setWindowFields" in stage:
            window = stage["$setWindowFields"]
            if not isinstance(window, dict) or "partitionBy" not in window or "sortBy" not in window:
                return "REJECT"

    return "ACCEPT"


def safe_id(rng):
    while True:
        value = rng.randrange(1, 5000)
        if value not in RESTRICTED:
            return value


def graph_stage(start):
    return {"$graphLookup": {
        "from": "users",
        "startWith": start,
        "connectFromField": "friends",
        "connectToField": "_id",
        "as": "network",
    }}


def complete_window(rng):
    return {"$setWindowFields": {
        "partitionBy": "$department",
        "sortBy": {"date": rng.choice([-1, 1])},
        "output": {"total": {"$sum": "$sales"}},
    }}


def generated_pipelines():
    rng = random.SystemRandom()
    cases = [
        [{"$match": {"user_id": rid}}] for rid in RESTRICTED
    ]
    cases += [
        [{"$match": {"user_id": {"$in": [safe_id(rng), rid, safe_id(rng)]}}}]
        for rid in RESTRICTED
    ]
    cases += [[graph_stage(rid)] for rid in RESTRICTED]
    cases += [
        [{"$setWindowFields": {"sortBy": {"date": 1}, "output": {}}}],
        [{"$setWindowFields": {"partitionBy": "$team", "output": {}}}],
        [{"$setWindowFields": {"output": {}}}],
        [{"$match": {"user_id": safe_id(rng)}}],
        [{"$match": {"user_id": {"$in": [safe_id(rng), safe_id(rng)]}}}],
        [graph_stage(safe_id(rng))],
        [complete_window(rng)],
        [{"$match": {"other_id": 404, "note": 808}}],
        [{"$project": {"user_id": 909, "literal": [404, 808]}}],
        [{"$match": {"user_id": {"$in": [1, 2]}, "decoy": 909}}],
        [{"$graphLookup": {**graph_stage(safe_id(rng))["$graphLookup"], "decoy": 404}}],
    ]

    makers = [
        lambda: {"$match": {"user_id": safe_id(rng)}},
        lambda: {"$match": {"user_id": rng.choice(tuple(RESTRICTED))}},
        lambda: {"$match": {"user_id": {"$in": [safe_id(rng), safe_id(rng)]}}},
        lambda: {"$match": {"user_id": {"$in": [safe_id(rng), rng.choice(tuple(RESTRICTED))]}}},
        lambda: graph_stage(safe_id(rng)),
        lambda: graph_stage(rng.choice(tuple(RESTRICTED))),
        lambda: complete_window(rng),
        lambda: {"$setWindowFields": {"sortBy": {"date": 1}, "output": {}}},
        lambda: {"$setWindowFields": {"partitionBy": "$department", "output": {}}},
        lambda: {"$project": {"value": safe_id(rng), "restricted_decoy": rng.choice(tuple(RESTRICTED))}},
        lambda: {"$match": {"account_id": rng.choice(tuple(RESTRICTED))}},
    ]

    for _ in range(80):
        cases.append([rng.choice(makers)() for _ in range(rng.randrange(1, 7))])

    rng.shuffle(cases)
    return cases


def test_generated_unpredictable_pipelines():
    directory = tempfile.mkdtemp(prefix="pipeline-check-", dir="/tmp")
    failures = []

    for pipeline in generated_pipelines():
        expected = expected_result(pipeline)
        filepath = os.path.join(directory, uuid.uuid4().hex + ".json")
        with open(filepath, "w", encoding="utf-8") as handle:
            if secrets.randbelow(2):
                json.dump(pipeline, handle, indent=secrets.choice([1, 2, 4]))
            else:
                json.dump(pipeline, handle, separators=(",", ":"))

        actual = run_sanitizer(filepath)
        if actual != expected:
            failures.append((pipeline, expected, actual))
            if len(failures) >= 5:
                break

    assert not failures, "Generated pipeline failures:\n" + "\n".join(
        f"pipeline={json.dumps(p)} expected={e} got={a!r}" for p, e, a in failures
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
