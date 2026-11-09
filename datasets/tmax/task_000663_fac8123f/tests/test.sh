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

SCRIPT_PATH = "/home/user/check_payload.sh"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_script(path, *extra_args):
    return subprocess.run(
        [SCRIPT_PATH, path, *extra_args],
        capture_output=True,
        timeout=10,
    )


def is_stale(document):
    stack = [(document, None)]
    while stack:
        node, parent = stack.pop()
        if (
            parent is not None
            and node["status"] == "active"
            and node["last_modified"] < parent["last_modified"]
        ):
            return True
        for child in node["dependencies"]:
            stack.append((child, node))
    return False


def write_and_check(path, document):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, separators=(",", ":"))

    before = open(path, "rb").read()
    expected = 1 if is_stale(document) else 0
    result = run_script(path)
    after = open(path, "rb").read()

    assert result.returncode == expected, (
        f"Expected exit {expected}, got {result.returncode} for generated payload"
    )
    assert after == before, "The payload JSON file was modified"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    # Preserve the original corpus assertions.
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    clean_failures = []
    evil_failures = []

    for file_path in clean_files:
        before = open(file_path, "rb").read()
        result = run_script(file_path)
        after = open(file_path, "rb").read()
        if result.returncode != 0:
            clean_failures.append((os.path.basename(file_path), result.returncode))
        assert after == before, f"Corpus file was modified: {file_path}"

    for file_path in evil_files:
        before = open(file_path, "rb").read()
        result = run_script(file_path)
        after = open(file_path, "rb").read()
        if result.returncode != 1:
            evil_failures.append((os.path.basename(file_path), result.returncode))
        assert after == before, f"Corpus file was modified: {file_path}"

    error_messages = []
    if evil_failures:
        bypassed_files = [f[0] for f in evil_failures]
        error_messages.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {bypassed_files}"
        )
    if clean_failures:
        modified_files = [f[0] for f in clean_failures]
        error_messages.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {modified_files}"
        )
    if error_messages:
        assert False, " | ".join(error_messages)


def test_generated_payloads_and_argument_count():
    rng = random.Random(secrets.randbits(128))

    with tempfile.TemporaryDirectory(prefix="payload-check-") as temp_dir:
        # Every case is written to the same neutrally named, unpredictable path,
        # preventing classification based on directory or filename labels.
        payload_path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")

        targeted = [
            {
                "node_id": "root",
                "last_modified": 100,
                "status": "active",
                "dependencies": [],
            },
            {
                "node_id": "root",
                "last_modified": 100,
                "status": "inactive",
                "dependencies": [
                    {
                        "node_id": "child",
                        "last_modified": 99,
                        "status": "inactive",
                        "dependencies": [],
                    }
                ],
            },
            {
                "node_id": "root",
                "last_modified": 100,
                "status": "inactive",
                "dependencies": [
                    {
                        "node_id": "child",
                        "last_modified": 100,
                        "status": "active",
                        "dependencies": [],
                    }
                ],
            },
            {
                "node_id": "root",
                "last_modified": 10,
                "status": "active",
                "dependencies": [
                    {
                        "node_id": "middle",
                        "last_modified": 50,
                        "status": "inactive",
                        "dependencies": [
                            {
                                "node_id": "leaf",
                                "last_modified": 49,
                                "status": "active",
                                "dependencies": [],
                            }
                        ],
                    }
                ],
            },
        ]

        for document in targeted:
            write_and_check(payload_path, document)

        # Exercise many independently generated tree shapes and derive each answer
        # directly from the stated parent/child rule.
        for case_number in range(60):
            root = {
                "node_id": f"n-{case_number}-0",
                "last_modified": rng.randint(-1000, 1000),
                "status": rng.choice(["active", "inactive", "pending"]),
                "dependencies": [],
            }
            nodes = [root]
            for index in range(1, rng.randint(3, 55)):
                parent = rng.choice(nodes)
                child = {
                    "node_id": f"n-{case_number}-{index}-{rng.getrandbits(32):08x}",
                    "last_modified": parent["last_modified"] + rng.randint(-30, 30),
                    "status": rng.choice(["active", "inactive", "pending"]),
                    "dependencies": [],
                }
                parent["dependencies"].append(child)
                nodes.append(child)
            write_and_check(payload_path, root)

        # Verify traversal through a substantially deep hierarchy.
        deep_root = {
            "node_id": "deep-0",
            "last_modified": 0,
            "status": "active",
            "dependencies": [],
        }
        cursor = deep_root
        for depth in range(1, 221):
            child = {
                "node_id": f"deep-{depth}",
                "last_modified": depth,
                "status": "active",
                "dependencies": [],
            }
            cursor["dependencies"].append(child)
            cursor = child
        write_and_check(payload_path, deep_root)

        cursor["dependencies"].append(
            {
                "node_id": "deep-stale-leaf",
                "last_modified": cursor["last_modified"] - 1,
                "status": "active",
                "dependencies": [],
            }
        )
        write_and_check(payload_path, deep_root)

        # The tool must accept exactly one argument.
        no_args = subprocess.run([SCRIPT_PATH], capture_output=True, timeout=10)
        two_args = subprocess.run(
            [SCRIPT_PATH, payload_path, payload_path], capture_output=True, timeout=10
        )
        assert no_args.returncode != 0, "Script accepted an invocation with no argument"
        assert two_args.returncode != 0, "Script accepted an invocation with two arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
