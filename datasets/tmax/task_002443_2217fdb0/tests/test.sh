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


def test_validator_script_exists():
    assert os.path.isfile("/home/user/validator.py"), "/home/user/validator.py does not exist."


def run_validator(validator_path, graph_path):
    return subprocess.run(
        ["python3", validator_path, graph_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_adversarial_corpus():
    validator_path = "/home/user/validator.py"

    clean_files = glob.glob("/app/clean/*.json")
    evil_files = glob.glob("/app/evil/*.json")

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_rejected = []
    for clean_file in clean_files:
        result = run_validator(validator_path, clean_file)
        if result.returncode != 0 or "VALID" not in result.stdout:
            clean_rejected.append(os.path.basename(clean_file))

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_validator(validator_path, evil_file)
        if result.returncode != 1 or "INVALID" not in result.stdout:
            evil_bypassed.append(os.path.basename(evil_file))

    error_messages = []
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean files rejected: {', '.join(clean_rejected)}")
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil files bypassed: {', '.join(evil_bypassed)}")

    assert not error_messages, " | ".join(error_messages)


def policy_accepts(graph):
    allowed_nodes = {"Service", "Database", "Backup"}
    allowed_edges = {"BELONGS_TO", "BACKUPS_TO"}
    nodes = {node["id"]: node for node in graph["nodes"]}

    if any(node["label"] not in allowed_nodes for node in graph["nodes"]):
        return False
    if any(edge["type"] not in allowed_edges for edge in graph["edges"]):
        return False
    if any(node["properties"]["retention_days"] > 30 for node in graph["nodes"] if node["label"] == "Backup"):
        return False

    for edge in graph["edges"]:
        if edge["type"] != "BACKUPS_TO":
            continue
        database = nodes[edge["source"]]
        backup = nodes[edge["target"]]
        if database["label"] != "Database" or backup["label"] != "Backup":
            continue
        if database["properties"]["region"] == backup["properties"]["region"]:
            continue

        has_global_service = False
        for belongs in graph["edges"]:
            if belongs["type"] != "BELONGS_TO" or belongs["target"] != database["id"]:
                continue
            service = nodes[belongs["source"]]
            if service["label"] == "Service" and service["properties"]["is_global"] is True:
                has_global_service = True
                break
        if not has_global_service:
            return False

    return True


def make_graph(*, retention, cross_region, is_global, service_label="Service", backup_edge="BACKUPS_TO"):
    ids = random.SystemRandom().sample(range(1000, 1000000), 3)
    region_a = "r-" + secrets.token_hex(6)
    region_b = "r-" + secrets.token_hex(6) if cross_region else region_a
    graph = {
        "nodes": [
            {"id": ids[0], "label": service_label, "properties": {"is_global": is_global}},
            {"id": ids[1], "label": "Database", "properties": {"region": region_a}},
            {"id": ids[2], "label": "Backup", "properties": {"region": region_b, "retention_days": retention}},
        ],
        "edges": [
            {"source": ids[0], "target": ids[1], "type": "BELONGS_TO"},
            {"source": ids[1], "target": ids[2], "type": backup_edge},
        ],
    }
    random.SystemRandom().shuffle(graph["nodes"])
    random.SystemRandom().shuffle(graph["edges"])
    return graph


def test_generated_policy_cases_on_neutral_paths():
    validator_path = "/home/user/validator.py"
    rng = random.SystemRandom()

    configurations = [
        dict(retention=30, cross_region=False, is_global=False),
        dict(retention=31, cross_region=False, is_global=False),
        dict(retention=14, cross_region=True, is_global=False),
        dict(retention=14, cross_region=True, is_global=True),
        dict(retention=14, cross_region=False, is_global=False, service_label="User"),
        dict(retention=14, cross_region=False, is_global=False, backup_edge="MIRRORS_TO"),
    ]

    for _ in range(30):
        configurations.append(dict(
            retention=rng.randint(1, 45),
            cross_region=bool(rng.getrandbits(1)),
            is_global=bool(rng.getrandbits(1)),
            service_label="User" if rng.randrange(8) == 0 else "Service",
            backup_edge="MIRRORS_TO" if rng.randrange(8) == 0 else "BACKUPS_TO",
        ))

    cases = []
    for config in configurations:
        graph = make_graph(**config)
        cases.append((graph, policy_accepts(graph)))
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="graphcheck_") as case_dir:
        for graph, should_accept in cases:
            graph_path = os.path.join(case_dir, secrets.token_hex(12) + ".json")
            with open(graph_path, "w", encoding="utf-8") as handle:
                json.dump(graph, handle)

            result = run_validator(validator_path, graph_path)
            expected_code = 0 if should_accept else 1
            expected_text = "VALID" if should_accept else "INVALID"
            if result.returncode != expected_code or expected_text not in result.stdout:
                failures.append(
                    f"expected {expected_text}/exit {expected_code}, got stdout={result.stdout!r}, "
                    f"stderr={result.stderr!r}, exit={result.returncode}, graph={graph!r}"
                )

    assert not failures, "Generated policy cases failed:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
