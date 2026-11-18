#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import random
import subprocess
import tempfile
import uuid
from collections import deque

import pytest

DETECTOR_BIN = "/home/user/detector"
DETECTOR_SRC = "/home/user/detector.c"
SANCTIONED_TXT = "/home/user/sanctioned.txt"
SANCTION_IMAGE = "/app/sanction_list.png"
CLEAN_DIR = "/app/clean"
EVIL_DIR = "/app/evil"
EXPECTED_SANCTIONS = [405, 819, 1002, 3319]


def run_detector(binary, graph, sanctions):
    result = subprocess.run(
        [binary, graph, sanctions],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Detector exited with {result.returncode}: {result.stderr}"
    output = result.stdout.strip()
    assert output in ("EVIL", "CLEAN"), f"Invalid detector output: {result.stdout!r}"
    return output


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_BIN), f"Detector binary not found at {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"Detector binary at {DETECTOR_BIN} is not executable"


def test_sanctioned_txt_exists():
    assert os.path.isfile(SANCTIONED_TXT), f"Sanctioned text file not found at {SANCTIONED_TXT}"


def test_sanctioned_txt_matches_image_ocr():
    assert os.path.isfile(SANCTION_IMAGE), f"Sanction image not found at {SANCTION_IMAGE}"
    ocr = subprocess.run(
        ["tesseract", SANCTION_IMAGE, "stdout", "--psm", "6"],
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    image_ids = [int(x) for x in re.findall(r"\b\d+\b", ocr.stdout)]
    assert image_ids == EXPECTED_SANCTIONS, f"OCR did not recover the supplied IDs: {image_ids}"

    with open(SANCTIONED_TXT, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert all(re.fullmatch(r"\s*\d+\s*", line) for line in lines), \
        "sanctioned.txt must contain one integer ID per line"
    submitted_ids = [int(line) for line in lines]
    assert submitted_ids == image_ids, \
        f"sanctioned.txt does not match the IDs extracted from the image: {submitted_ids}"


def test_adversarial_corpus():
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]

    assert len(evil_files) > 0, "No evil CSV files found."
    assert len(clean_files) > 0, "No clean CSV files found."

    evil_bypassed = []
    clean_modified = []

    for evil_file in evil_files:
        try:
            output = run_detector(DETECTOR_BIN, evil_file, SANCTIONED_TXT)
            if output != "EVIL":
                evil_bypassed.append((os.path.basename(evil_file), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(evil_file), str(e)))

    for clean_file in clean_files:
        try:
            output = run_detector(DETECTOR_BIN, clean_file, SANCTIONED_TXT)
            if output != "CLEAN":
                clean_modified.append((os.path.basename(clean_file), output))
        except Exception as e:
            clean_modified.append((os.path.basename(clean_file), str(e)))

    error_msgs = []
    if evil_bypassed:
        bypassed_names = [f[0] for f in evil_bypassed]
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {bypassed_names}")
    if clean_modified:
        modified_names = [f[0] for f in clean_modified]
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (flagged as EVIL or failed): {modified_names}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


@pytest.fixture(scope="session")
def rebuilt_detector(tmp_path_factory):
    assert os.path.isfile(DETECTOR_SRC), f"C source not found at {DETECTOR_SRC}"
    out = tmp_path_factory.mktemp("build") / ("detector_" + uuid.uuid4().hex)
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", DETECTOR_SRC, "-o", str(out)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"detector.c does not compile with gcc:\n{result.stderr}"
    assert out.is_file() and os.access(out, os.X_OK)
    return str(out)


def oracle(edges, sanctions):
    adjacency = {}
    for src, dst in edges:
        adjacency.setdefault(src, []).append(dst)
    sanctioned = set(sanctions)
    for start in sanctions:
        queue = deque([(start, 0)])
        seen = {start}
        while queue:
            node, depth = queue.popleft()
            if depth == 3:
                continue
            for nxt in adjacency.get(node, []):
                new_depth = depth + 1
                if nxt in sanctioned and nxt != start:
                    return "EVIL"
                if nxt not in seen:
                    seen.add(nxt)
                    queue.append((nxt, new_depth))
    return "CLEAN"


def make_case(rng, want_evil):
    while True:
        ids = rng.sample(range(1, 9999), 22)
        sanctions = ids[:4]
        intermediates = ids[4:]
        edges = []

        if want_evil:
            start, target = rng.sample(sanctions, 2)
            hops = rng.randint(1, 3)
            chain = [start] + rng.sample(intermediates, hops - 1) + [target]
        else:
            start, target = rng.sample(sanctions, 2)
            chain = [start] + rng.sample(intermediates, 3) + [target]
        edges.extend(zip(chain, chain[1:]))

        # Include cycles, self-loops, disconnected components, and random directionality.
        edges.append((sanctions[0], sanctions[0]))
        for _ in range(rng.randint(8, 18)):
            src, dst = rng.sample(ids, 2)
            edges.append((src, dst))
        rng.shuffle(edges)

        expected = oracle(edges, sanctions)
        if (expected == "EVIL") == want_evil:
            return sanctions, edges, expected


def test_generated_graphs_and_rebuilt_c_source(rebuilt_detector, tmp_path):
    rng = random.Random(secrets.randbits(128))
    binaries = [DETECTOR_BIN, rebuilt_detector]

    for index in range(40):
        sanctions, edges, expected = make_case(rng, want_evil=(index % 2 == 0))
        token = uuid.uuid4().hex
        graph_path = tmp_path / f"network_{token}.csv"
        sanctions_path = tmp_path / f"entities_{uuid.uuid4().hex}.txt"

        with open(graph_path, "w", encoding="utf-8") as f:
            for src, dst in edges:
                amount = rng.randint(1, 100000) / 100.0
                f.write(f"{src},{dst},{amount:.2f}\n")
        with open(sanctions_path, "w", encoding="utf-8") as f:
            for entity in sanctions:
                f.write(f"{entity}\n")

        # Re-derive every answer from the generated graph rather than labels or paths.
        assert expected == oracle(edges, sanctions)
        for binary in binaries:
            actual = run_detector(binary, str(graph_path), str(sanctions_path))
            assert actual == expected, \
                f"Incorrect result for generated case {index}: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
