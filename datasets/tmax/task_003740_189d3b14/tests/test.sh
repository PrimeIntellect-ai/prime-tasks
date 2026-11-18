#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

import cv2
import pytest

SCRIPT = '/home/user/filter_datasets.py'


def run_filter(input_dir, output_dir):
    try:
        subprocess.run(
            ['python3', SCRIPT, str(input_dir), str(output_dir)],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Script execution failed.\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}')
    except subprocess.TimeoutExpired:
        pytest.fail('Filtering script timed out.')


def test_video_graph_csv():
    """Verify that the CSV contains the edges actually decoded from the video."""
    csv_path = '/home/user/video_graph.csv'
    video_path = '/app/experiment_001.mp4'
    assert os.path.exists(csv_path), f'File {csv_path} does not exist.'

    expected = []
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f'Could not decode {video_path}'
    frame_index = 0
    while True:
        ok, image = cap.read()
        if not ok:
            break
        assert image.shape[:2] == (10, 10), f'Unexpected frame dimensions: {image.shape[:2]}'
        for source in range(10):
            for target in range(10):
                if source != target and float(image[source, target].mean()) > 128:
                    expected.append((frame_index, source, target))
        frame_index += 1
    cap.release()
    assert frame_index == 50, f'Expected 50 decoded frames, found {frame_index}.'

    with open(csv_path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['frame', 'source', 'target'], f'Incorrect header in {csv_path}: {header}'
        rows = list(reader)
        assert len(rows) == 85, f'Expected exactly 85 edges extracted from the video, but found {len(rows)}.'

    actual = []
    for number, row in enumerate(rows, start=2):
        assert len(row) == 3, f'CSV row {number} does not contain exactly three fields: {row}'
        try:
            actual.append(tuple(int(value) for value in row))
        except ValueError:
            pytest.fail(f'CSV row {number} contains a non-integer value: {row}')

    assert Counter(actual) == Counter(expected), 'CSV edge values do not match the decoded video frames.'


def test_filter_datasets_script_exists():
    """Verify that the filtering script exists and is a regular file."""
    assert os.path.exists(SCRIPT), f'Filtering script {SCRIPT} does not exist.'
    assert os.path.isfile(SCRIPT), f'Filtering script {SCRIPT} is not a regular file.'


def test_filter_datasets_adversarial_corpus():
    """Retain the supplied-corpus checks."""
    clean_in = '/app/corpus/clean'
    evil_in = '/app/corpus/evil'
    assert os.path.exists(clean_in), f'Clean corpus missing at {clean_in}'
    assert os.path.exists(evil_in), f'Evil corpus missing at {evil_in}'

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        run_filter(clean_in, clean_out)
        run_filter(evil_in, evil_out)

        clean_in_files = {f for f in os.listdir(clean_in) if f.endswith('.csv')}
        clean_out_files = set(os.listdir(clean_out))
        missing_clean = clean_in_files - clean_out_files
        modified_clean = []
        for name in clean_in_files.intersection(clean_out_files):
            with open(os.path.join(clean_in, name), 'r', encoding='utf-8') as f1, \
                 open(os.path.join(clean_out, name), 'r', encoding='utf-8') as f2:
                if f1.read() != f2.read():
                    modified_clean.append(name)
        total_clean_issues = len(missing_clean) + len(modified_clean)
        if total_clean_issues > 0:
            msg = f'{total_clean_issues} of {len(clean_in_files)} clean modified or missing. '
            if missing_clean:
                msg += f'Missing: {sorted(missing_clean)}. '
            if modified_clean:
                msg += f'Modified: {sorted(modified_clean)}.'
            pytest.fail(msg)

        evil_in_files = {f for f in os.listdir(evil_in) if f.endswith('.csv')}
        evil_out_files = set(os.listdir(evil_out))
        bypassed_evil = evil_out_files.intersection(evil_in_files)
        if bypassed_evil:
            pytest.fail(f'{len(bypassed_evil)} of {len(evil_in_files)} evil bypassed. Offending files: {sorted(bypassed_evil)}')


def oracle_valid(edges):
    nodes = {node for _, source, target in edges for node in (source, target)}
    if not edges:
        return True
    minimum = min(frame for frame, _, _ in edges) - 4
    maximum = max(frame for frame, _, _ in edges)
    for node in nodes:
        for start in range(minimum, maximum + 1):
            count = sum(
                1 for frame, source, target in edges
                if start <= frame <= start + 4 and (source == node or target == node)
            )
            if count > 7:
                return False
    return True


def write_dataset(path, edges):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['frame', 'source', 'target'])
        writer.writerows(edges)


def test_filter_on_fresh_hidden_cases():
    """Exercise schema, incoming/outgoing counts, gaps, and numeric sliding windows."""
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory() as root:
        input_dir = Path(root) / ('input_' + secrets.token_hex(8))
        output_dir = Path(root) / ('output_' + secrets.token_hex(8))
        input_dir.mkdir()
        output_dir.mkdir()
        expected = set()

        cases = [
            [(10, 3, i) for i in range(4, 11)],
            [(0, 2, i) for i in range(10, 14)] + [(5, 2, i) for i in range(20, 24)],
            [(2, 0, 8), (2, 9, 0), (3, 0, 10), (3, 11, 0),
             (4, 0, 12), (4, 13, 0), (5, 0, 14)],
            [(2, 0, 8), (2, 9, 0), (3, 0, 10), (3, 11, 0),
             (4, 0, 12), (4, 13, 0), (5, 0, 14), (6, 15, 0)],
            [],
        ]

        for _ in range(18):
            edges = []
            node_count = rng.randint(6, 14)
            for _ in range(rng.randint(3, 45)):
                source = rng.randrange(node_count)
                target = rng.randrange(node_count - 1)
                if target >= source:
                    target += 1
                edges.append((rng.randint(-4, 28), source, target))
            cases.append(edges)

        for edges in cases:
            name = secrets.token_hex(12) + '.csv'
            write_dataset(input_dir / name, edges)
            if oracle_valid(edges):
                expected.add(name)

        malformed = {
            secrets.token_hex(12) + '.csv': 'frame,source\n0,1\n',
            secrets.token_hex(12) + '.csv': 'source,frame,target\n1,0,2\n',
            secrets.token_hex(12) + '.csv': 'frame,source,target,extra\n0,1,2,x\n',
            secrets.token_hex(12) + '.csv': 'frame,source,target\nnot-a-frame,1,2\n',
        }
        for name, contents in malformed.items():
            (input_dir / name).write_text(contents, encoding='utf-8')

        ignored_name = secrets.token_hex(12) + '.txt'
        (input_dir / ignored_name).write_text('frame,source,target\n0,1,2\n', encoding='utf-8')
        original_bytes = {name: (input_dir / name).read_bytes() for name in expected}

        run_filter(input_dir, output_dir)

        produced = {p.name for p in output_dir.iterdir()}
        assert produced == expected, f'Wrong files selected. Expected {sorted(expected)}, got {sorted(produced)}'
        for name in expected:
            assert (output_dir / name).read_bytes() == original_bytes[name], f'Valid file {name} was modified.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
