#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import pytest

ETL_DIR = '/home/user/etl'
SOURCE = os.path.join(ETL_DIR, 'process.go')
OUTPUT = os.path.join(ETL_DIR, 'output.jsonl')
BINARY = '/tmp/etl_process_test'

EXPECTED = {
    (0, 10, 'hello', 1), (0, 10, 'thank', 1), (0, 10, 'you', 1),
    (0, 10, 'for', 1), (0, 10, 'calling', 1), (0, 10, 'support', 1),
    (0, 10, 'my', 1), (0, 10, 'account', 1), (0, 10, 'is', 1),
    (0, 10, 'locked', 1), (0, 10, 'and', 1), (0, 10, 'i', 1),
    (0, 10, 'cannot', 1),
    (10, 20, 'login', 1), (10, 20, 'to', 1), (10, 20, 'the', 1),
    (10, 20, 'system', 1), (10, 20, 'i', 1), (10, 20, 'understand', 1),
    (10, 20, 'let', 1), (10, 20, 'me', 1), (10, 20, 'help', 1),
    (10, 20, 'you', 1),
    (20, 30, 'unlock', 1), (20, 30, 'the', 1), (20, 30, 'account', 1),
}


def test_go_pipeline_and_output():
    assert os.path.isfile(SOURCE), f'Expected Go source not found at {SOURCE}'
    with open(SOURCE, 'r', encoding='utf-8') as f:
        source = f.read()

    assert re.search(r'package\s+main\b', source), 'process.go must be an executable Go program'
    assert 'os.Open' in source, 'process.go must open and process a transcript file'
    assert any(marker in source for marker in (
        'bufio.NewScanner', 'bufio.NewReader', 'json.NewDecoder',
        'csv.NewReader', 'xml.NewDecoder', '.Read(',
    )), 'process.go must process its transcript as a stream'
    forbidden = ('os.ReadFile', 'ioutil.ReadFile', 'io.ReadAll', 'ioutil.ReadAll')
    assert not any(marker in source for marker in forbidden), (
        'process.go uses a whole-file read API instead of streaming the transcript'
    )

    build = subprocess.run(
        ['go', 'build', '-o', BINARY, SOURCE], cwd=ETL_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120,
    )
    assert build.returncode == 0, f'process.go did not compile:\n{build.stdout}'

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run = subprocess.run(
        [BINARY], cwd=ETL_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120,
    )
    assert run.returncode == 0, f'Compiled Go ETL failed:\n{run.stdout}'
    assert os.path.isfile(OUTPUT), f'Go program did not create {OUTPUT}'

    rows = []
    with open(OUTPUT, 'r', encoding='utf-8') as f:
        for line_number, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                pytest.fail(f'Invalid JSON at line {line_number}: {exc}')

            assert isinstance(row, dict), f'Line {line_number} is not a JSON object'
            assert set(row) == {'bucket_start', 'bucket_end', 'word', 'count'}, (
                f'Line {line_number} does not have the required schema: {row}'
            )
            start, end = row['bucket_start'], row['bucket_end']
            word, count = row['word'], row['count']
            assert type(start) is int and start >= 0 and start % 10 == 0, (
                f'Invalid bucket_start at line {line_number}: {start!r}'
            )
            assert type(end) is int and end == start + 10, (
                f'Invalid bucket_end at line {line_number}: {end!r}'
            )
            assert isinstance(word, str) and word and word == word.lower() and all(c.isalnum() for c in word), (
                f'Word is not normalized at line {line_number}: {word!r}'
            )
            assert type(count) is int and count > 0, (
                f'Invalid count at line {line_number}: {count!r}'
            )
            rows.append((start, end, word, count))

    assert rows, 'No output rows were produced'
    assert len(rows) == len(set((s, w) for s, _, w, _ in rows)), (
        'Duplicate bucket/word rows found; frequencies must be aggregated'
    )

    # Preserve the original pair-overlap assertion.
    expected_pairs = {(s, w) for s, _, w, _ in EXPECTED}
    agent_pairs = {(s, w) for s, _, w, _ in rows}
    pair_union = len(expected_pairs | agent_pairs)
    assert pair_union > 0, 'No valid (bucket_start, word) pairs found in the output.'
    pair_score = len(expected_pairs & agent_pairs) / pair_union
    assert pair_score >= 0.70, (
        f'Jaccard similarity score {pair_score:.3f} is below the threshold of 0.700.'
    )

    # Also score the complete required records so wrong ends or counts cannot pass.
    agent_records = set(rows)
    record_union = len(EXPECTED | agent_records)
    record_score = len(EXPECTED & agent_records) / record_union
    assert record_score >= 0.70, (
        f'Full-record Jaccard score {record_score:.3f} is below 0.700; '
        'bucket ends and aggregated counts must be correct.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
