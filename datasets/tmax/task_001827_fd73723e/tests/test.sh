#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = '/home/user/detector'
SOURCE_PATH = '/home/user/detector.cpp'


def test_detector_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not a compiled executable."


def test_detector_on_corpora():
    clean_dir = '/app/corpora/clean'
    evil_dir = '/app/corpora/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for cf in clean_files:
        try:
            result = subprocess.run([BINARY_PATH, cf], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_failures.append(os.path.basename(cf))
        except Exception as e:
            clean_failures.append(f"{os.path.basename(cf)} (error: {e})")

    evil_failures = []
    for ef in evil_files:
        try:
            result = subprocess.run([BINARY_PATH, ef], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_failures.append(os.path.basename(ef))
        except Exception as e:
            evil_failures.append(f"{os.path.basename(ef)} (error: {e})")

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean files misclassified or failed: {', '.join(clean_failures)}")
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil files bypassed or failed: {', '.join(evil_failures)}")

    assert not error_msg, " | ".join(error_msg)


@pytest.fixture(scope='session')
def rebuilt_binary():
    assert os.path.isfile(SOURCE_PATH), f"C++ source {SOURCE_PATH} is missing."
    output = f"/tmp/detector_rebuilt_{secrets.token_hex(8)}"
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', output],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"detector.cpp does not compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


@pytest.fixture(scope='session')
def video_threshold():
    with tempfile.TemporaryDirectory(prefix='video_frames_') as frame_dir:
        pattern = os.path.join(frame_dir, 'frame_%06d.png')
        result = subprocess.run(
            ['ffmpeg', '-loglevel', 'error', '-i', '/app/network_capture.mp4', '-vsync', '0', pattern],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Unable to extract video frames: {result.stderr}"
        frames = sorted(os.path.join(frame_dir, n) for n in os.listdir(frame_dir) if n.endswith('.png'))
        assert frames, "ffmpeg extracted no frames from the supplied video."

        frame_average_degrees = []
        for frame in frames:
            extracted = subprocess.run(
                ['/app/extract_edges.py', frame],
                capture_output=True,
                text=True,
                timeout=2,
            )
            assert extracted.returncode == 0, f"extract_edges.py failed for {frame}"
            rows = csv.DictReader(extracted.stdout.splitlines())
            adjacency = {}
            for row in rows:
                source = row['Source'].strip()
                target = row['Target'].strip()
                adjacency.setdefault(source, set()).add(target)
                adjacency.setdefault(target, set()).add(source)
            assert adjacency, f"No graph was extracted from {frame}"
            frame_average_degrees.append(sum(len(v) for v in adjacency.values()) / len(adjacency))

        return 1.5 * (sum(frame_average_degrees) / len(frame_average_degrees))


def graph_max_degree(edges):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, set()).add(target)
        adjacency.setdefault(target, set()).add(source)
    return max((len(neighbors) for neighbors in adjacency.values()), default=0)


def test_detector_on_unseen_neutral_paths(rebuilt_binary, video_threshold):
    boundary_degree = max(1, math.floor(video_threshold))
    evil_degree = boundary_degree + 1

    matching = [(1000 + 2 * i, 1001 + 2 * i) for i in range(18)]
    cycle = [(2000 + i, 2000 + ((i + 1) % 14)) for i in range(14)]
    clique = [(3000 + i, 3000 + j) for i in range(boundary_degree + 1) for j in range(i + 1, boundary_degree + 1)]
    star = [(4000, 4100 + i) for i in range(evil_degree)]
    mixed_star = [(5000, 5100 + i) for i in range(evil_degree + 2)] + [(6000 + 2 * i, 6001 + 2 * i) for i in range(10)]

    cases = [matching, cycle, clique, star, mixed_star]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"graphs_{secrets.token_hex(8)}_") as case_dir:
        generated = []
        for edges in cases:
            path = os.path.join(case_dir, f"{secrets.token_hex(12)}.csv")
            shuffled_edges = list(edges)
            random.SystemRandom().shuffle(shuffled_edges)
            with open(path, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['Source', 'Target'])
                writer.writerows(shuffled_edges)
            expected = 'EVIL' if graph_max_degree(edges) > video_threshold else 'CLEAN'
            generated.append((path, expected))

        assert {expected for _, expected in generated} == {'CLEAN', 'EVIL'}

        for binary in (BINARY_PATH, rebuilt_binary):
            for path, expected in generated:
                result = subprocess.run([binary, path], capture_output=True, text=True, timeout=2)
                assert result.returncode == 0, f"{binary} failed on an unseen CSV: {result.stderr}"
                assert result.stdout.splitlines() == [expected], (
                    f"{binary} returned {result.stdout!r}, expected exactly one line containing {expected}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
