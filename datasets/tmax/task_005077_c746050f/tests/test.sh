#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import tempfile
from collections import Counter

import pytest

VENDOR = "/app/vendor/bash-graph-tools-1.0"
GEXTRACT = os.path.join(VENDOR, "bin", "gextract")
SOURCE = os.path.join(VENDOR, "src", "gextract")
SCRIPT = "/home/user/validate_backup.sh"


def assert_gextract_works():
    assert os.path.isfile(GEXTRACT), f"Executable not found at {GEXTRACT}. Did you fix the Makefile and run make install?"
    assert os.access(GEXTRACT, os.X_OK), f"File at {GEXTRACT} is not executable."
    result = subprocess.run([GEXTRACT, "--version"], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running {GEXTRACT} --version failed with exit code {result.returncode}."
    assert "bash-graph-tools v1.0" in result.stdout, f"Expected output 'bash-graph-tools v1.0', got: {result.stdout}"


def test_vendored_package_fixed():
    # Preserve the original final-artifact assertions.
    assert_gextract_works()
    assert os.path.isfile(SOURCE), f"Vendored source missing at {SOURCE}"
    with open(GEXTRACT, "rb") as installed, open(SOURCE, "rb") as source:
        assert installed.read() == source.read(), "bin/gextract is not the installed vendored utility"

    makefile = os.path.join(VENDOR, "Makefile")
    assert os.path.isfile(makefile), f"Makefile not found at {makefile}"
    with open(makefile, encoding="utf-8") as fh:
        make_text = fh.read()
    assert "/usr/local/broken_bgt" not in make_text, "The broken hardcoded installation path remains in the Makefile"

    # Prove that the repaired build process itself installs into the required local bin directory.
    os.unlink(GEXTRACT)
    result = subprocess.run(
        ["make", "-B", "install"], cwd=VENDOR, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"make install failed:\n{result.stdout}\n{result.stderr}"
    assert_gextract_works()
    with open(GEXTRACT, "rb") as installed, open(SOURCE, "rb") as source:
        assert installed.read() == source.read(), "make install did not install src/gextract into the local bin directory"


def run_classifier(edges, nodes):
    result = subprocess.run([SCRIPT, edges, nodes], capture_output=True, timeout=15)
    assert result.returncode in (0, 1), f"Classifier must exit 0 or 1, got {result.returncode}: {result.stderr!r}"
    return result.returncode


def test_backup_classifier_script_on_original_corpus():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_shards = [os.path.join(clean_dir, d) for d in os.listdir(clean_dir) if os.path.isdir(os.path.join(clean_dir, d))]
    evil_shards = [os.path.join(evil_dir, d) for d in os.listdir(evil_dir) if os.path.isdir(os.path.join(evil_dir, d))]

    clean_failed = []
    for shard in clean_shards:
        edges = os.path.join(shard, "edges.json")
        nodes = os.path.join(shard, "nodes.csv")
        if os.path.isfile(edges) and os.path.isfile(nodes) and run_classifier(edges, nodes) != 0:
            clean_failed.append(os.path.basename(shard))

    evil_bypassed = []
    for shard in evil_shards:
        edges = os.path.join(shard, "edges.json")
        nodes = os.path.join(shard, "nodes.csv")
        if os.path.isfile(edges) and os.path.isfile(nodes) and run_classifier(edges, nodes) == 0:
            evil_bypassed.append(os.path.basename(shard))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_shards)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_shards)} clean modified (rejected): {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def oracle(node_rows, edges):
    node_ids = {row[0] for row in node_rows}
    if any(edge["src"] not in node_ids or edge["dst"] not in node_ids for edge in edges):
        return 1
    counts = Counter(edge["src"] for edge in edges)
    return 1 if any(count > 50 for count in counts.values()) else 0


def test_backup_classifier_on_generated_unlabeled_shards():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script at {SCRIPT} is not executable."

    token = secrets.token_hex(8)
    ids = [f"vertex_{token}_{i}" for i in range(8)]
    rows = [(node, random.choice(["user", "service", "host"]), str(2020 + i % 6)) for i, node in enumerate(ids)]
    missing_a = f"absent_{secrets.token_hex(8)}"
    missing_b = f"absent_{secrets.token_hex(8)}"

    cases = [
        (rows, []),
        (rows, [{"src": ids[0], "dst": ids[(i % 7) + 1]} for i in range(50)]),
        (rows, [{"src": ids[0], "dst": ids[(i % 7) + 1]} for i in range(51)]),
        (rows, [{"src": missing_a, "dst": ids[1]}]),
        (rows, [{"src": ids[2], "dst": missing_b}]),
        (rows, [{"src": ids[i % 4], "dst": ids[(i + 3) % 8]} for i in range(37)]),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"backup-check-{token}-") as root:
        for index, (node_rows, edges) in enumerate(cases):
            case_dir = os.path.join(root, f"item-{secrets.token_hex(6)}")
            os.mkdir(case_dir)
            json_path = os.path.join(case_dir, f"graph-{secrets.token_hex(4)}.data")
            csv_path = os.path.join(case_dir, f"metadata-{secrets.token_hex(4)}.data")
            with open(json_path, "w", encoding="utf-8") as fh:
                json.dump({"edges": edges}, fh)
            with open(csv_path, "w", encoding="utf-8", newline="") as fh:
                writer = csv.writer(fh)
                writer.writerow(["node_id", "node_type", "created_at"])
                writer.writerows(node_rows)

            expected = oracle(node_rows, edges)
            actual = run_classifier(json_path, csv_path)
            assert actual == expected, f"Generated case {index} returned {actual}, expected {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
