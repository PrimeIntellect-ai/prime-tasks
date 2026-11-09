#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
DATA = HOME / 'data.csv'
WEIGHTS = HOME / 'weights.csv'
PREDICTIONS = HOME / 'predictions.csv'


def check_original_predictions():
    assert PREDICTIONS.is_file(), f'Output file {PREDICTIONS} is missing. Did you run the C++ program?'

    expected_content = [
        'id,score,prediction',
        '1,0.2642,1',
        '2,0.2636,1',
        '3,0.0000,0',
        '4,-0.9000,0',
        '5,0.0462,0',
        '6,0.0457,0',
    ]

    with PREDICTIONS.open('r') as f:
        actual_content = [line.strip() for line in f if line.strip()]

    assert len(actual_content) == len(expected_content), \
        f'Expected {len(expected_content)} lines, but got {len(actual_content)}.'
    for i, (actual, expected) in enumerate(zip(actual_content, expected_content)):
        assert actual == expected, \
            f"Line {i + 1} mismatch. Expected '{expected}', got '{actual}'."


def score_text(text, weights):
    counts = [0] * 26
    for ch in text:
        lower = ch.lower()
        if 'a' <= lower <= 'z':
            counts[ord(lower) - ord('a')] += 1
    total = sum(counts)
    if total == 0:
        return 0.0
    return sum((counts[i] / total) * weights[i] for i in range(26))


def make_challenge():
    rng = random.SystemRandom()
    weights = [rng.randint(-900, 900) / 1000.0 for _ in range(26)]
    weights[rng.randrange(26)] = rng.randint(500, 900) / 1000.0
    weights[rng.randrange(26)] = -rng.randint(500, 900) / 1000.0

    max_i = max(range(26), key=lambda i: weights[i])
    min_i = min(range(26), key=lambda i: weights[i])
    alphabet = 'abcdefghijklmnopqrstuvwxyz'

    texts = [
        '98765 !@#$%, -- no letters here',
        (alphabet[max_i].upper() + alphabet[max_i]) * rng.randint(5, 11),
        alphabet[min_i] * rng.randint(7, 14),
        'AbCdEfGhIjKlMnOpQrStUvWxYz, zYxWvUtSrQpOnMlKjIhGfEdCbA!',
    ]

    while len(texts) < 9:
        chars = []
        for _ in range(rng.randint(25, 80)):
            if rng.random() < 0.72:
                ch = rng.choice(alphabet)
                chars.append(ch.upper() if rng.random() < 0.45 else ch)
            else:
                chars.append(rng.choice(' 0123456789,!?._-'))
        text = ''.join(chars)
        score = score_text(text, weights)
        scaled = abs(score * 10000.0 - (round(score * 10000.0 - 0.5) + 0.5))
        if abs(score) > 0.0001 and abs(score - 0.25) > 0.002 and scaled > 0.00001:
            texts.append(text)

    base_id = rng.randint(1000, 9000)
    ids = [base_id + i * rng.randint(2, 9) for i in range(len(texts))]

    data_lines = ['id,text']
    expected = ['id,score,prediction']
    for row_id, text in zip(ids, texts):
        data_lines.append(f'{row_id},"{text}"')
        score = score_text(text, weights)
        expected.append(f'{row_id},{score:.4f},{1 if score > 0.25 else 0}')

    order = list(range(26))
    rng.shuffle(order)
    weight_lines = ['char,weight'] + [f'{alphabet[i]},{weights[i]:.3f}' for i in order]
    return '\n'.join(data_lines) + '\n', '\n'.join(weight_lines) + '\n', expected


def check_cpp_pipeline():
    sources = sorted(p for p in HOME.rglob('*.cpp') if p.is_file())
    assert sources, 'No C++ source file was found under /home/user.'

    compile_groups = [(p,) for p in sources]
    if len(sources) > 1:
        compile_groups.append(tuple(sources))

    data_bytes = DATA.read_bytes()
    weights_bytes = WEIGHTS.read_bytes()
    prediction_existed = PREDICTIONS.exists()
    prediction_bytes = PREDICTIONS.read_bytes() if prediction_existed else b''
    challenge_data, challenge_weights, expected = make_challenge()
    failures = []

    try:
        DATA.write_text(challenge_data)
        WEIGHTS.write_text(challenge_weights)

        for index, group in enumerate(compile_groups):
            binary = Path(tempfile.gettempdir()) / f'candidate_pipeline_{os.getpid()}_{index}'
            command = ['g++', '-O3', *map(str, group), '-o', str(binary)]
            compiled = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, timeout=30)
            if compiled.returncode != 0:
                failures.append(f"Compilation failed for {', '.join(map(str, group))}: {compiled.stderr[-500:]}")
                continue

            DATA.write_text(challenge_data)
            WEIGHTS.write_text(challenge_weights)
            try:
                PREDICTIONS.unlink()
            except FileNotFoundError:
                pass

            try:
                run = subprocess.run([str(binary)], cwd=str(HOME), stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, timeout=15)
            except subprocess.TimeoutExpired:
                failures.append(f"Program built from {', '.join(map(str, group))} timed out")
                continue

            if run.returncode != 0:
                failures.append(f"Program built from {', '.join(map(str, group))} exited with {run.returncode}: {run.stderr[-500:]}")
                continue
            if not PREDICTIONS.is_file():
                failures.append(f"Program built from {', '.join(map(str, group))} did not create predictions.csv")
                continue

            actual = PREDICTIONS.read_text().splitlines()
            if actual == expected:
                return
            failures.append(
                f"Program built from {', '.join(map(str, group))} produced incorrect results on generated inputs. "
                f"Expected {expected!r}, got {actual!r}"
            )

        raise AssertionError('No submitted C++ program passed compilation and execution checks. ' + ' | '.join(failures))
    finally:
        DATA.write_bytes(data_bytes)
        WEIGHTS.write_bytes(weights_bytes)
        if prediction_existed:
            PREDICTIONS.write_bytes(prediction_bytes)
        else:
            try:
                PREDICTIONS.unlink()
            except FileNotFoundError:
                pass


check_original_predictions()
check_cpp_pipeline()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
