#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest


def get_sanitiser_cmd():
    sanitisers = glob.glob('/home/user/sanitiser.*')
    if not sanitisers:
        pytest.fail("No sanitiser script found at /home/user/sanitiser.*")

    script = sanitisers[0]
    ext = os.path.splitext(script)[1]

    if ext == '.py':
        return ['python3', script]
    elif ext == '.rb':
        return ['ruby', script]
    elif ext == '.js':
        return ['node', script]
    elif ext == '.sh':
        return ['bash', script]
    elif os.access(script, os.X_OK):
        return [script]
    pytest.fail(f"Unknown extension for sanitiser script: {script}")


def candidate_tool_commands():
    seen = set()
    for root in ('/home/user', '/app'):
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if not d.startswith('.')]
            for name in files:
                path = os.path.join(directory, name)
                if path in seen or not os.path.isfile(path):
                    continue
                seen.add(path)
                ext = os.path.splitext(path)[1].lower()
                if ext == '.py':
                    yield ['python3', path]
                elif ext == '.rb':
                    yield ['ruby', path]
                elif ext == '.js':
                    yield ['node', path]
                elif ext == '.sh':
                    yield ['bash', path]
                elif os.access(path, os.X_OK) and ext not in ('.png', '.json', '.csv', '.txt'):
                    yield [path]


def test_shortest_path_output():
    """Test that the shortest path is correctly computed and saved."""
    path_file = "/home/user/shortest_path.txt"
    assert os.path.isfile(path_file), f"Missing shortest path output file: {path_file}"

    with open(path_file, 'r') as f:
        content = f.read().strip()

    expected = "ALPHA_01,BETA_04,GAMMA_02,NODE_OMEGA"
    assert content == expected, f"Incorrect shortest path. Expected '{expected}', got '{content}'"


def test_pathfinding_tool_recomputes_from_both_backups():
    """Execute the submitted tool against a fresh graph instead of trusting a fixed output."""
    csv_path = '/app/data/relational/data.csv'
    json_path = '/app/data/document/data.json'
    output_path = '/home/user/shortest_path.txt'

    token = uuid.uuid4().hex.upper()
    middle = f'MID_{token}'
    decoy1 = f'DECOY_A_{token}'
    decoy2 = f'DECOY_B_{token}'
    expected = f'ALPHA_01,{middle},NODE_OMEGA'

    with open(csv_path, 'rb') as f:
        old_csv = f.read()
    with open(json_path, 'rb') as f:
        old_json = f.read()
    old_output = None
    if os.path.isfile(output_path):
        with open(output_path, 'rb') as f:
            old_output = f.read()

    try:
        with open(csv_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['source_id', 'dest_id', 'weight'])
            writer.writerow(['ALPHA_01', middle, 1])
            writer.writerow(['ALPHA_01', decoy1, 1])
        with open(json_path, 'w') as f:
            json.dump([
                {'source_id': middle, 'dest_id': 'NODE_OMEGA', 'weight': 2},
                {'source_id': decoy1, 'dest_id': decoy2, 'weight': 1},
                {'source_id': decoy2, 'dest_id': 'NODE_OMEGA', 'weight': 10}
            ], f)

        commands = list(candidate_tool_commands())
        assert commands, 'No executable pathfinding tool was found under /home/user or /app'

        observed = []
        for command in commands:
            try:
                if os.path.exists(output_path):
                    os.remove(output_path)
                result = subprocess.run(
                    command, cwd='/home/user', capture_output=True, text=True, timeout=20
                )
                content = ''
                if os.path.isfile(output_path):
                    with open(output_path) as f:
                        content = f.read().strip()
                observed.append((command, result.returncode, content))
                if result.returncode == 0 and content == expected:
                    break
            except (OSError, subprocess.TimeoutExpired):
                continue
        else:
            pytest.fail(
                "No submitted tool recomputed the shortest path from the changed CSV and JSON "
                f"fixtures; expected '{expected}'"
            )
    finally:
        with open(csv_path, 'wb') as f:
            f.write(old_csv)
        with open(json_path, 'wb') as f:
            f.write(old_json)
        if old_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(old_output)


def test_sanitiser_adversarial_corpus():
    """Test the sanitiser script against the clean and evil corpora."""
    cmd_base = get_sanitiser_cmd()

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run(cmd_base + [cf], capture_output=True, text=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))
        assert result.stdout.strip(), f"Sanitiser emitted no data for clean file {os.path.basename(cf)}"
        assert 'A' in result.stdout and 'B' in result.stdout, \
            f"Sanitiser did not preserve the valid record in {os.path.basename(cf)}"

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run(cmd_base + [ef], capture_output=True, text=True)
        # It must exit with code 1 OR filter out the malicious nodes (exit 0 but output doesn't contain malicious loop)
        if result.returncode == 0:
            if '__malicious_loop__' in result.stdout:
                evil_failures.append(os.path.basename(ef))
        assert result.returncode == 1, \
            f"Entirely malicious file {os.path.basename(ef)} must exit with code 1"

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_sanitiser_filters_fresh_mixed_input():
    cmd_base = get_sanitiser_cmd()
    token = uuid.uuid4().hex
    source = f'SRC_{token}'
    dest = f'DST_{token}'
    malicious = f'EVIL_{token}'

    mixed = [
        {'source_id': source, 'dest_id': dest, 'weight': 7},
        {'source_id': malicious, 'dest_id': malicious, 'weight': -1,
         'tag': '__malicious_loop__'}
    ]
    all_bad = [
        {'source_id': malicious, 'dest_id': malicious, 'weight': -1,
         'tag': '__malicious_loop__'}
    ]

    with tempfile.TemporaryDirectory() as td:
        mixed_path = os.path.join(td, 'mixed.json')
        bad_path = os.path.join(td, 'bad.json')
        with open(mixed_path, 'w') as f:
            json.dump(mixed, f)
        with open(bad_path, 'w') as f:
            json.dump(all_bad, f)

        result = subprocess.run(cmd_base + [mixed_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, 'A mixed backup containing a valid record must be accepted'
        assert result.stdout.strip(), 'Sanitiser emitted no output for a mixed backup'
        assert source in result.stdout and dest in result.stdout, 'Valid record was not preserved'
        assert '__malicious_loop__' not in result.stdout and malicious not in result.stdout, \
            'Malicious loop record was not filtered'

        result = subprocess.run(cmd_base + [bad_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 1, 'An entirely malicious backup must exit with code 1'
        assert '__malicious_loop__' not in result.stdout, 'Malicious data was emitted'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
