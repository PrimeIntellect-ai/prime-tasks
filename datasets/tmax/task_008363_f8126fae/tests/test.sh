#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_submission.py
import os
import random
import re
import subprocess
from collections import Counter
from pathlib import Path

HOME = Path('/home/user')
FASTA = HOME / 'data' / 'sequences.fasta'
SOURCE = HOME / 'simulate.c'
DT_FILE = HOME / 'dt_chosen.txt'
RESULT_FILE = HOME / 'result.txt'
BINARY = Path('/tmp/submission_simulate')


def make_original_fixture():
    rng = random.Random(123)
    chunks = []
    for i in range(500):
        length = rng.randint(100, 200)
        seq = ''.join(rng.choices(['A', 'C', 'G', 'T'], k=length))
        chunks.append(f'>seq_{i}\n{seq}\n')
    return ''.join(chunks).encode('ascii')


def make_challenge_fixture():
    rng = random.Random(int.from_bytes(os.urandom(32), 'big'))
    chunks = []
    for i in range(500):
        length = rng.randint(80, 240)
        seq = ''.join(rng.choices(['A', 'C', 'G', 'T'], k=length))
        chunks.append(f'>challenge_{i}\n{seq}\n')
    return ''.join(chunks).encode('ascii')


def parse_k_values(data):
    values = []
    seq = []
    for raw_line in data.decode('ascii').splitlines():
        line = raw_line.strip()
        if line.startswith('>'):
            if seq:
                joined = ''.join(seq)
                values.append((joined.count('G') + joined.count('C')) / len(joined))
                seq = []
        elif line:
            seq.append(line)
    if seq:
        joined = ''.join(seq)
        values.append((joined.count('G') + joined.count('C')) / len(joined))
    assert len(values) == 500, f'Expected 500 FASTA records, found {len(values)}'
    return values


def rk4_step(y, k, dt):
    def f(value):
        return k * value - 0.05 * value * value
    k1 = f(y)
    k2 = f(y + dt * k1 / 2.0)
    k3 = f(y + dt * k2 / 2.0)
    k4 = f(y + dt * k3)
    return y + dt * (k1 + 2.0*k2 + 2.0*k3 + k4) / 6.0


def simulate_population(k_values, dt):
    total = 0.0
    compensation = 0.0
    steps = int(round(100.0 / dt))
    for k in k_values:
        y = 2.0
        for _ in range(steps):
            y = rk4_step(y, k, dt)
        corrected = y - compensation
        new_total = total + corrected
        compensation = (new_total - total) - corrected
        total = new_total
    return total


def expected_values(data):
    k_values = parse_k_values(data)
    dt = 1.0
    previous = simulate_population(k_values, dt)
    for _ in range(30):
        current = simulate_population(k_values, dt / 2.0)
        if abs(previous - current) < 1e-5:
            return f'{dt:.4f}', f'{previous:.6f}'
        dt /= 2.0
        previous = current
    raise AssertionError('Reference convergence did not terminate')


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', text)


def inspect_source(text):
    code = strip_comments(text)
    assert re.search(r'\bdouble\b', code), 'The implementation does not use double precision'

    # Accept conventional named RK4 stages, four explicit derivative calls, or
    # a four-element loop implementation. Also require the characteristic 1/6 weight.
    lower = code.lower()
    named_stages = all(re.search(rf'\b(?:k|stage|slope)_?{i}\b', lower) for i in range(1, 5))
    calls = re.findall(r'\b([A-Za-z_]\w*)\s*\(', code)
    ignored = {'if', 'for', 'while', 'switch', 'sizeof', 'printf', 'fprintf', 'sprintf', 'snprintf', 'fopen', 'fclose'}
    counts = Counter(name for name in calls if name not in ignored)
    four_calls = any(count >= 4 for count in counts.values())
    loop_stages = bool(re.search(r'\[\s*4\s*\]', code) and re.search(r'\bfor\s*\(', code))
    sixth_weight = bool(re.search(r'/\s*6(?:\.0*)?\b|1(?:\.0*)?\s*/\s*6(?:\.0*)?\b|0\.1666', code))
    assert (named_stages or four_calls or loop_stages) and sixth_weight, 'No standard four-stage RK4 implementation was found'

    # Recognize the canonical Kahan compensation update and its common
    # sign-reversed equivalent. Comments cannot satisfy this check.
    canonical = re.search(
        r'\b(?P<c>[A-Za-z_]\w*)\s*=\s*\(\s*(?P<t>[A-Za-z_]\w*)\s*-\s*(?P<s>[A-Za-z_]\w*)\s*\)\s*-\s*(?P<y>[A-Za-z_]\w*)\s*;',
        code,
    )
    reversed_form = re.search(
        r'\b(?P<c>[A-Za-z_]\w*)\s*=\s*\(\s*(?P<s>[A-Za-z_]\w*)\s*-\s*(?P<t>[A-Za-z_]\w*)\s*\)\s*\+\s*(?P<y>[A-Za-z_]\w*)\s*;',
        code,
    )
    match = canonical or reversed_form
    assert match, 'No Kahan compensation update was found'
    names = match.groupdict()
    c, t, s, y = (re.escape(names[n]) for n in ('c', 't', 's', 'y'))
    if canonical:
        adjusted = re.search(rf'\b{y}\s*=\s*[^;]+\s*-\s*{c}\s*;', code)
    else:
        adjusted = re.search(rf'\b{y}\s*=\s*[^;]+\s*\+\s*{c}\s*;', code)
    combined = re.search(rf'\b{t}\s*=\s*{s}\s*\+\s*{y}\s*;', code)
    committed = re.search(rf'\b{s}\s*=\s*{t}\s*;', code)
    assert adjusted and combined and committed, 'The compensation update is not part of a complete Kahan summation sequence'


def restore_fixture(data):
    FASTA.parent.mkdir(parents=True, exist_ok=True)
    if FASTA.exists() and not FASTA.is_file():
        FASTA.unlink()
    FASTA.write_bytes(data)


def read_exact_output(path, pattern):
    assert path.is_file() and not path.is_symlink(), f'Missing regular output file: {path}'
    content = path.read_text(encoding='ascii')
    assert re.fullmatch(pattern, content), f'Invalid formatting in {path}: {content!r}'
    return content.rstrip('\n')


def run_case(fixture, expected_dt, expected_result):
    restore_fixture(fixture)
    for output in (DT_FILE, RESULT_FILE):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [str(BINARY)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180, check=False,
    )
    assert completed.returncode == 0, f'Compiled program exited with status {completed.returncode}: {completed.stderr.decode(errors="replace")}'
    assert FASTA.read_bytes() == fixture, 'The program modified the input FASTA fixture'

    actual_dt = read_exact_output(DT_FILE, r'[0-9]+\.[0-9]{4}\n?')
    actual_result = read_exact_output(RESULT_FILE, r'-?[0-9]+\.[0-9]{6}\n?')
    assert actual_dt == expected_dt, f'Expected step size {expected_dt}, got {actual_dt}'
    assert actual_result == expected_result, f'Expected final concentration {expected_result}, got {actual_result}'


def main():
    original = make_original_fixture()
    assert FASTA.is_file() and not FASTA.is_symlink(), f'Missing original fixture: {FASTA}'
    assert FASTA.read_bytes() == original, 'The original 500-sequence FASTA fixture was altered'
    assert SOURCE.is_file() and not SOURCE.is_symlink(), f'The C program was not found at {SOURCE}'

    source_text = SOURCE.read_text(encoding='utf-8')
    inspect_source(source_text)

    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(SOURCE), '-o', str(BINARY), '-lm'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=False,
    )
    assert compile_result.returncode == 0, f'simulate.c did not compile: {compile_result.stderr.decode(errors="replace")}'

    challenge = make_challenge_fixture()
    challenge_expected = expected_values(challenge)
    original_expected = expected_values(original)

    try:
        # The hidden fixture prevents precomputed output files or hard-coded fixture answers.
        run_case(challenge, *challenge_expected)
        # Run last on the required fixture so successful submissions leave the requested outputs.
        run_case(original, *original_expected)
    finally:
        restore_fixture(original)


if __name__ == '__main__':
    main()
PY_EOF

python3 /tmp/verify_submission.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
