#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/analyze.c')
BINARY = Path('/tmp/agent_analyze')
METRICS = Path('/home/user/metrics.txt')
TRAIN = Path('/app/events.csv')
TEST = Path('/app/test_events.csv')
MAPPING = Path('/app/mapping.png')

FIXED_TRAIN = [
    ['A', 'B', 'C', 'D', 'E'],
    ['A', 'A', 'B', 'C'],
    ['B', 'D', 'E', 'A'],
    ['C', 'E', 'E'],
    ['A', 'B', 'D'],
    ['E', 'D', 'C', 'B', 'A'],
    ['A', 'C', 'E'],
    ['B', 'B', 'B'],
    ['D', 'A', 'C'],
    ['E', 'A', 'B', 'C', 'D'],
]
FIXED_TEST = [
    ['A', 'B', 'E'],
    ['C', 'D', 'A'],
    ['E', 'E'],
]

DYNAMIC_TRAIN = [
    ['E'],
    ['D', 'A'],
    ['C', 'E', 'B'],
    ['B', 'D', 'A', 'E'],
    ['A', 'C', 'C', 'D', 'B'],
    ['D'],
    ['E', 'B'],
    ['C', 'A', 'E'],
    ['B', 'B', 'D', 'C'],
    ['A', 'E', 'D', 'B', 'C'],
]
DYNAMIC_TEST = [
    ['D', 'A', 'E', 'B'],
    ['C', 'C', 'D'],
    ['E', 'B', 'A'],
]


def write_csv(path, sequences):
    with path.open('w', encoding='utf-8', newline='') as f:
        f.write('id,event_sequence\n')
        for i, seq in enumerate(sequences, 1):
            f.write(f"{i},{' '.join(seq)}\n")


def reference_perplexity(train, test):
    vocab = ['A', 'B', 'C', 'D', 'E']
    counts = {u: {v: 0 for v in vocab} for u in ['<s>'] + vocab}
    unigram = {u: 0 for u in ['<s>'] + vocab}
    for seq in train:
        prev = '<s>'
        unigram[prev] += 1
        for token in seq:
            counts[prev][token] += 1
            unigram[token] += 1
            prev = token

    total_log = 0.0
    total_tokens = 0
    for seq in test:
        prev = '<s>'
        for token in seq:
            probability = (counts[prev][token] + 1) / (unigram[prev] + 5)
            total_log += math.log2(probability)
            total_tokens += 1
            prev = token
    return 2 ** (-(total_log / total_tokens))


def parse_exact_metrics():
    assert METRICS.is_file(), 'The C program did not create /home/user/metrics.txt'
    content = METRICS.read_text(encoding='utf-8')
    match = re.fullmatch(
        r'Bootstrap_Mean_Length: ([+-]?(?:\d+\.\d{4}))\n'
        r'Test_Perplexity: ([+-]?(?:\d+\.\d{4}))\n?',
        content,
    )
    assert match, 'metrics.txt must contain exactly the two required lines with four decimal places'
    bootstrap = float(match.group(1))
    perplexity = float(match.group(2))
    assert math.isfinite(bootstrap) and math.isfinite(perplexity)
    return bootstrap, perplexity


def run_case(train, test, bootstrap_tolerance=0.05):
    write_csv(TRAIN, train)
    write_csv(TEST, test)
    METRICS.unlink(missing_ok=True)
    subprocess.run(
        ['timeout', '30s', str(BINARY)],
        cwd='/home/user',
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    bootstrap, perplexity = parse_exact_metrics()

    expected_mean = sum(map(len, train)) / len(train)
    assert abs(bootstrap - expected_mean) <= bootstrap_tolerance, (
        f'Bootstrap mean {bootstrap:.4f} is not consistent with 10,000 row-bootstrap samples; '
        f'expected it near {expected_mean:.4f}'
    )

    expected_perplexity = reference_perplexity(train, test)
    error = abs(perplexity - expected_perplexity)
    assert error <= 0.05, (
        f'Test_Perplexity error {error:.4f} is greater than threshold 0.05. '
        f'Reference Perplexity: {expected_perplexity:.4f}, Agent Perplexity: {perplexity:.4f}'
    )


def main():
    assert SOURCE.is_file() and not SOURCE.is_symlink(), '/home/user/analyze.c is missing or is not a regular C source file'
    assert MAPPING.is_file(), '/app/mapping.png is missing'

    source = SOURCE.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'mapping\.png', source, re.I), 'The C pipeline does not reference the mapping image'
    assert re.search(r'tesseract', source, re.I), 'The C pipeline does not perform OCR with tesseract'
    assert re.search(r'events\.csv', source, re.I) and re.search(r'test_events\.csv', source, re.I), 'The C program must read both CSV inputs'
    assert re.search(r'\b10000\b', source), 'No 10,000-sample bootstrap loop is present in the C source'
    assert re.search(r'\b(?:rand|rand_r|random)\s*\(', source), 'No random sampling operation is present in the C source'

    ocr = subprocess.run(
        ['tesseract', str(MAPPING), 'stdout'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout
    for code, token_id in zip('ABCDE', range(1, 6)):
        assert re.search(rf'\b{code}\s*[:=-]?\s*{token_id}\b', ocr), 'The supplied mapping image is not parseable as the required mapping'

    subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(SOURCE), '-lm', '-o', str(BINARY)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    original_train = TRAIN.read_bytes() if TRAIN.exists() else None
    original_test = TEST.read_bytes() if TEST.exists() else None
    try:
        # Preserve the original verifier's reference assertion on the specified data.
        run_case(FIXED_TRAIN, FIXED_TEST, bootstrap_tolerance=0.04)
        # A second derived case rejects fixed metrics and confirms that the compiled artifact reads its inputs.
        run_case(DYNAMIC_TRAIN, DYNAMIC_TEST, bootstrap_tolerance=0.05)
    finally:
        if original_train is None:
            TRAIN.unlink(missing_ok=True)
        else:
            TRAIN.write_bytes(original_train)
        if original_test is None:
            TEST.unlink(missing_ok=True)
        else:
            TEST.write_bytes(original_test)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
