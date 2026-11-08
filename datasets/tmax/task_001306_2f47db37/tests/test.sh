#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest


def get_executable():
    candidates = [
        "/home/user/filter_payload.py",
        "/home/user/filter_payload.js",
        "/home/user/filter_payload.sh"
    ]
    for c in candidates:
        if os.path.isfile(c):
            if c.endswith(".py"):
                return ["python3", c]
            elif c.endswith(".js"):
                return ["node", c]
            elif c.endswith(".sh"):
                return ["bash", c]
    return None


def test_adversarial_corpus():
    executable = get_executable()
    assert executable is not None, "Could not find filter_payload script (.py, .js, or .sh) in /home/user/"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, f"No clean JSON files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil JSON files found in {evil_dir}"

    clean_failed = []
    for f in clean_files:
        res = subprocess.run(executable + [f], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        res = subprocess.run(executable + [f], capture_output=True)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(f))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not error_messages, " | ".join(error_messages)


ALLOWED_EDGES = {
    ("User", "PURCHASES", "Product"),
    ("User", "REVIEWS", "Product"),
    ("Product", "BELONGS_TO", "Category"),
}


def payload_is_valid(value):
    if not isinstance(value, dict):
        return False
    source = value.get("source")
    target = value.get("target")
    relationship = value.get("relationship")
    if not isinstance(source, dict) or not isinstance(target, dict):
        return False
    edge = (source.get("label"), relationship, target.get("label"))
    target_id = target.get("id")
    return edge in ALLOWED_EDGES and isinstance(target_id, str) and "*" not in target_id


def document_is_valid(raw):
    try:
        return payload_is_valid(json.loads(raw))
    except (ValueError, TypeError):
        return False


def random_id(prefix):
    return prefix + secrets.token_hex(8)


def make_base():
    source_label, relationship, target_label = random.choice(tuple(ALLOWED_EDGES))
    return {
        "source": {"label": source_label, "id": random_id("s-")},
        "relationship": relationship,
        "target": {"label": target_label, "id": random_id("t-")},
    }


def mutate(payload, mutation):
    value = copy.deepcopy(payload)
    if mutation == "wildcard":
        value["target"]["id"] = "*"
    elif mutation == "embedded_wildcard":
        value["target"]["id"] = "prefix*" + secrets.token_hex(3)
    elif mutation == "array":
        value["target"]["id"] = [random_id("t-"), random_id("t-")]
    elif mutation == "object":
        value["target"]["id"] = {"value": random_id("t-")}
    elif mutation == "number":
        value["target"]["id"] = random.randint(1, 100000)
    elif mutation == "boolean":
        value["target"]["id"] = random.choice([True, False])
    elif mutation == "null":
        value["target"]["id"] = None
    elif mutation == "missing_target_id":
        del value["target"]["id"]
    elif mutation == "bad_relationship":
        value["relationship"] = "EDGE_" + secrets.token_hex(5)
    elif mutation == "bad_source_label":
        value["source"]["label"] = "Node_" + secrets.token_hex(5)
    elif mutation == "bad_target_label":
        value["target"]["label"] = "Node_" + secrets.token_hex(5)
    elif mutation == "wrong_edge_tuple":
        value["source"]["label"] = "Product"
        value["relationship"] = "PURCHASES"
        value["target"]["label"] = "User"
    elif mutation == "source_not_object":
        value["source"] = random_id("s-")
    elif mutation == "target_not_object":
        value["target"] = random_id("t-")
    elif mutation == "missing_relationship":
        del value["relationship"]
    return value


def test_generated_mixed_corpus():
    executable = get_executable()
    assert executable is not None, "Could not find filter_payload script (.py, .js, or .sh) in /home/user/"

    mutations = [
        "wildcard", "embedded_wildcard", "array", "object", "number",
        "boolean", "null", "missing_target_id", "bad_relationship",
        "bad_source_label", "bad_target_label", "wrong_edge_tuple",
        "source_not_object", "target_not_object", "missing_relationship",
    ]

    documents = []
    for i in range(180):
        payload = make_base()
        if i % 4 != 0:
            payload = mutate(payload, random.choice(mutations))
        style = i % 3
        if style == 0:
            raw = json.dumps(payload, separators=(",", ":"))
        elif style == 1:
            raw = json.dumps(payload, indent=2)
        else:
            raw = "\n  " + json.dumps(payload) + "\n"
        documents.append(raw)

    documents.extend([
        "{",
        "not-json-" + secrets.token_hex(8),
        '[{"source": {}, "relationship": "PURCHASES", "target": {}}]',
        'null',
        '"' + secrets.token_hex(8) + '"',
        '{"source":{"label":"User"},"relationship":"PURCHASES","target":{"label":"Product","id":"x"}} trailing',
    ])
    random.SystemRandom().shuffle(documents)

    failures = []
    with tempfile.TemporaryDirectory(prefix="payload-check-") as temp_dir:
        cases = []
        for raw in documents:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(raw)
            cases.append((path, document_is_valid(raw)))

        for path, expected_valid in cases:
            try:
                result = subprocess.run(executable + [path], capture_output=True, timeout=5)
                actual_valid = result.returncode == 0
            except subprocess.TimeoutExpired:
                actual_valid = False
            if actual_valid != expected_valid:
                failures.append(
                    f"{os.path.basename(path)} expected {'accept' if expected_valid else 'reject'}"
                )

    assert not failures, f"Generated mixed corpus failures ({len(failures)}): " + ", ".join(failures[:20])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
