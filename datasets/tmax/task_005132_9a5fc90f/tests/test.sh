#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

BINARY_PATH = "/home/user/detector/target/release/detector"
VIDEO_PATH = "/app/topology_scan.mp4"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_adversarial_corpus():
    assert os.path.isfile(BINARY_PATH), "Binary not found"

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found"
    assert len(clean_files) > 0, "No clean corpus files found"

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        cmd = [BINARY_PATH, "--video", VIDEO_PATH, "--log", filepath]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_bypassed.append((os.path.basename(filepath), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(filepath), str(e)))

    for filepath in clean_files:
        cmd = [BINARY_PATH, "--video", VIDEO_PATH, "--log", filepath]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_modified.append((os.path.basename(filepath), output))
        except Exception as e:
            clean_modified.append((os.path.basename(filepath), str(e)))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: " + ", ".join([f"{f} (got {o})" for f, o in evil_bypassed]))
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: " + ", ".join([f"{f} (got {o})" for f, o in clean_modified]))

    if error_msgs:
        pytest.fail("\n".join(error_msgs))


def write_video(path, edges, split_edges, rng):
    groups = [set(), set()]
    shuffled = list(edges)
    rng.shuffle(shuffled)
    for i, edge in enumerate(shuffled):
        groups[i % 2].add(edge)

    out = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 1, (100, 100), isColor=True)
    assert out.isOpened(), "Could not create generated MP4"
    for frame_number in range(30):
        frame = np.full((100, 100, 3), 255, dtype=np.uint8)
        visible = groups[frame_number % 2] if split_edges else edges
        for a, b in visible:
            frame[b, a] = (0, 0, 0)
            frame[a, b] = (0, 0, 0)
        out.write(frame)
    out.release()


def derive_edges(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open generated video {video_path}"
    edges = set()
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        for y in range(20):
            for x in range(20):
                if x != y and np.array_equal(frame[y, x], np.array([0, 0, 0], dtype=np.uint8)):
                    edges.add((min(x, y), max(x, y)))
    cap.release()
    assert frames == 30, f"Generated video decoded as {frames} frames instead of 30"
    return edges


def high_risk_hubs(edges):
    degrees = [0] * 20
    for a, b in edges:
        degrees[a] += 1
        degrees[b] += 1
    return sorted(range(20), key=lambda node: (-degrees[node], node))[:3]


def reference_classification(edges, transactions):
    hubs = set(high_risk_hubs(edges))
    hub_transactions = sorted(
        (tx for tx in transactions if tx["router_id"] in hubs),
        key=lambda tx: tx["timestamp_sec"],
    )
    for tx in hub_transactions:
        start = tx["timestamp_sec"]
        total = sum(
            other["bytes"]
            for other in hub_transactions
            if start <= other["timestamp_sec"] < start + 60
        )
        if total > 10000:
            return "REJECT"
    return "ACCEPT"


def run_case(video_path, edges, transactions, directory):
    log_path = os.path.join(directory, uuid.uuid4().hex + ".json")
    with open(log_path, "w", encoding="utf-8") as handle:
        json.dump(transactions, handle)

    expected = reference_classification(edges, transactions)
    result = subprocess.run(
        [BINARY_PATH, "--video", video_path, "--log", log_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Detector exited with {result.returncode}; stderr was {result.stderr!r}"
    )
    assert result.stdout == expected + "\n", (
        f"Expected exactly {expected!r} followed by a newline, got {result.stdout!r}"
    )


def txs(router, base, first, second, gap):
    return [
        {"tx_id": uuid.uuid4().hex, "timestamp_sec": base, "router_id": router, "bytes": first},
        {"tx_id": uuid.uuid4().hex, "timestamp_sec": base + gap, "router_id": router, "bytes": second},
    ]


def test_generated_topologies_and_sliding_windows():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    with tempfile.TemporaryDirectory(prefix="detector-check-") as directory:
        # Three randomly selected stars make these nodes the unique top three hubs.
        selected_hubs = rng.sample(list(range(3, 20)), 3)
        star_edges = set()
        for hub in selected_hubs:
            for node in range(20):
                if node != hub:
                    star_edges.add((min(hub, node), max(hub, node)))

        star_video = os.path.join(directory, uuid.uuid4().hex + ".mp4")
        write_video(star_video, star_edges, True, rng)
        decoded_star_edges = derive_edges(star_video)
        assert set(high_risk_hubs(decoded_star_edges)) == set(selected_hubs), (
            "Generated star topology did not survive video encoding"
        )

        # A complete graph gives all nodes equal degree, so index tie-breaking must
        # select exactly nodes 0, 1, and 2.
        complete_edges = {(a, b) for a in range(20) for b in range(a + 1, 20)}
        tie_video = os.path.join(directory, uuid.uuid4().hex + ".mp4")
        write_video(tie_video, complete_edges, False, rng)
        decoded_tie_edges = derive_edges(tie_video)
        assert high_risk_hubs(decoded_tie_edges) == [0, 1, 2], (
            "Generated tie topology did not survive video encoding"
        )

        base = rng.randint(1000, 100000)

        # Exercise every dynamically selected hub with an over-threshold window.
        for hub in selected_hubs:
            first = rng.randint(4500, 6000)
            second = 10001 - first + rng.randint(0, 1000)
            run_case(
                star_video,
                decoded_star_edges,
                txs(hub, base, first, second, rng.randint(1, 59)),
                directory,
            )

        nonhub = next(node for node in range(20) if node not in selected_hubs)
        run_case(star_video, decoded_star_edges, txs(nonhub, base, 7000, 7000, 10), directory)
        run_case(star_video, decoded_star_edges, txs(selected_hubs[0], base, 5000, 5000, 59), directory)
        run_case(star_video, decoded_star_edges, txs(selected_hubs[1], base, 7000, 7000, 60), directory)

        # Identical traffic must change classification when only the video changes.
        shared = txs(selected_hubs[0], base + 500, 6000, 6000, 20)
        run_case(star_video, decoded_star_edges, shared, directory)
        run_case(tie_video, decoded_tie_edges, shared, directory)

        # Verify the lower-index boundary of the all-node degree tie.
        run_case(tie_video, decoded_tie_edges, txs(2, base, 6000, 6000, 20), directory)
        run_case(tie_video, decoded_tie_edges, txs(3, base, 6000, 6000, 20), directory)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
