#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import subprocess
import tempfile
import uuid

import pytest

THRESHOLD_FILE = "/home/user/threshold.txt"
SCRIPT_FILE = "/home/user/detect.py"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
MIN_BOTS = 14


def test_threshold_file():
    assert os.path.isfile(THRESHOLD_FILE), f"Threshold file missing at {THRESHOLD_FILE}"
    with open(THRESHOLD_FILE, "r") as f:
        content = f.read().strip()
    assert content == "14", f"Expected threshold to be '14', but got '{content}'"


def test_detect_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Detection script missing at {SCRIPT_FILE}"


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_FILE), f"Detection script missing at {SCRIPT_FILE}"

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        result = subprocess.run(["python3", SCRIPT_FILE, evil_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "EVIL":
            evil_bypassed.append(f"{os.path.basename(evil_file)} (output: {output})")

    for clean_file in clean_files:
        result = subprocess.run(["python3", SCRIPT_FILE, clean_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "CLEAN":
            clean_modified.append(f"{os.path.basename(clean_file)} (output: {output})")

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def oracle(rows):
    commanded = {}
    attackers = {}
    for source, target, relation in rows:
        if relation == "COMMAND":
            commanded.setdefault(source, set()).add(target)
        elif relation == "ATTACK":
            attackers.setdefault(target, set()).add(source)

    for bots in commanded.values():
        for attacking_bots in attackers.values():
            if len(bots & attacking_bots) >= MIN_BOTS:
                return "EVIL"
    return "CLEAN"


def test_generated_unseen_graphs():
    assert os.path.isfile(SCRIPT_FILE), f"Detection script missing at {SCRIPT_FILE}"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    def ident(prefix):
        return f"{prefix}_{uuid.uuid4().hex}"

    cases = []

    # Exact-threshold topology with arbitrary identifiers.
    master, target = ident("n"), ident("n")
    bots = [ident("n") for _ in range(14)]
    cases.append([(master, b, "COMMAND") for b in bots] +
                 [(b, target, "ATTACK") for b in bots])

    # Boundary case: one bot short.
    master, target = ident("n"), ident("n")
    bots = [ident("n") for _ in range(13)]
    cases.append([(master, b, "COMMAND") for b in bots] +
                 [(b, target, "ATTACK") for b in bots])

    # Fourteen commanded bots, but their attacks are split across destinations.
    master, target1, target2 = ident("n"), ident("n"), ident("n")
    bots = [ident("n") for _ in range(14)]
    cases.append([(master, b, "COMMAND") for b in bots] +
                 [(b, target1 if i < 7 else target2, "ATTACK") for i, b in enumerate(bots)])

    # Commands and attacks each involve fourteen bots, but not the same bots.
    master, target = ident("n"), ident("n")
    commanded_bots = [ident("n") for _ in range(14)]
    attacking_bots = [ident("n") for _ in range(14)]
    cases.append([(master, b, "COMMAND") for b in commanded_bots] +
                 [(b, target, "ATTACK") for b in attacking_bots])

    # Duplicate rows must not be counted as distinct bots.
    master, bot, target = ident("n"), ident("n"), ident("n")
    cases.append([(master, bot, "COMMAND"), (bot, target, "ATTACK")] * 30)

    # Bots split between two masters do not form one qualifying command fanout.
    master1, master2, target = ident("n"), ident("n"), ident("n")
    bots = [ident("n") for _ in range(16)]
    cases.append([(master1 if i < 8 else master2, b, "COMMAND") for i, b in enumerate(bots)] +
                 [(b, target, "ATTACK") for b in bots])

    # A larger qualifying graph with duplicate and unrelated traffic.
    master, target = ident("n"), ident("n")
    bots = [ident("n") for _ in range(18)]
    rows = ([(master, b, "COMMAND") for b in bots] +
            [(b, target, "ATTACK") for b in bots] +
            [(master, bots[0], "COMMAND")] * 10)
    noise_nodes = [ident("n") for _ in range(80)]
    for _ in range(350):
        rows.append((rng.choice(noise_nodes), rng.choice(noise_nodes),
                     rng.choice(["COMMAND", "ATTACK"])))
    cases.append(rows)

    # Randomized graphs prevent reliance on filenames, row order, or fixed labels.
    for plant_topology in (False, True, False, True, False, True, False, True):
        nodes = [ident("n") for _ in range(70)]
        rows = []
        for _ in range(rng.randint(120, 260)):
            rows.append((rng.choice(nodes), rng.choice(nodes),
                         rng.choice(["COMMAND", "ATTACK"])))
        if plant_topology:
            master, target = ident("n"), ident("n")
            bots = [ident("n") for _ in range(rng.randint(14, 20))]
            rows.extend((master, b, "COMMAND") for b in bots)
            rows.extend((b, target, "ATTACK") for b in bots)
        cases.append(rows)

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"graphs_{uuid.uuid4().hex}_") as temp_dir:
        for index, rows in enumerate(cases):
            rng.shuffle(rows)
            path = os.path.join(temp_dir, f"{uuid.uuid4().hex}.csv")
            with open(path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["source", "target", "relation"])
                writer.writerows(rows)

            expected = oracle(rows)
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_FILE, path],
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Detection script timed out on generated case {index}")

            assert result.returncode == 0, (
                f"Detection script failed on generated case {index}: {result.stderr}"
            )
            assert result.stdout.strip() == expected, (
                f"Generated case {index}: expected {expected}, got "
                f"{result.stdout.strip()!r}; stderr={result.stderr!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
