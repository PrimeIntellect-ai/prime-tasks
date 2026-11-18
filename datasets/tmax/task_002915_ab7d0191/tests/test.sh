#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import random
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

PROJECT_DIR = Path('/home/user/graph_filter')
LINE_RE = re.compile(r'^(ACCEPT|REJECT) ([^\\s]+)$')


def run_graph_filter(target_dir: str, expected_files: set[str]) -> dict[str, str]:
    assert PROJECT_DIR.is_dir(), f'Rust project directory {PROJECT_DIR} does not exist.'
    assert (PROJECT_DIR / 'Cargo.toml').is_file(), f'Cargo.toml not found in {PROJECT_DIR}.'

    try:
        result = subprocess.run(
            ['cargo', 'run', '--release', '--', target_dir],
            cwd=str(PROJECT_DIR),
            capture_output=True,
            text=True,
            timeout=120,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        assert False, f'cargo run failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}'
    except subprocess.TimeoutExpired:
        assert False, 'cargo run timed out after 120 seconds.'

    lines = result.stdout.splitlines()
    assert len(lines) == len(expected_files), (
        f'Expected exactly {len(expected_files)} stdout lines, got {len(lines)}. '
        f'Stdout: {result.stdout!r}'
    )

    results = {}
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match, f'Malformed stdout line: {line!r}'
        status, filename = match.groups()
        assert filename not in results, f'Duplicate output for {filename!r}'
        results[filename] = status

    assert set(results) == expected_files, (
        f'Output filenames differ from directory contents. '
        f'Missing: {sorted(expected_files - set(results))}; '
        f'Extra: {sorted(set(results) - expected_files)}'
    )
    return results


def test_clean_corpus():
    clean_dir = Path('/app/corpora/clean')
    assert clean_dir.is_dir(), f'Clean corpus directory {clean_dir} missing.'
    expected_files = {f.name for f in clean_dir.glob('*.txt')}
    assert expected_files, 'No text files found in clean corpus.'

    results = run_graph_filter(str(clean_dir), expected_files)
    rejected_files = [f for f, status in results.items() if status == 'REJECT']
    assert not rejected_files, (
        f'{len(rejected_files)} of {len(expected_files)} clean files rejected: '
        f'{", ".join(rejected_files)}'
    )


def test_evil_corpus():
    evil_dir = Path('/app/corpora/evil')
    assert evil_dir.is_dir(), f'Evil corpus directory {evil_dir} missing.'
    expected_files = {f.name for f in evil_dir.glob('*.txt')}
    assert expected_files, 'No text files found in evil corpus.'

    results = run_graph_filter(str(evil_dir), expected_files)
    accepted_files = [f for f, status in results.items() if status == 'ACCEPT']
    assert not accepted_files, (
        f'{len(accepted_files)} of {len(expected_files)} evil files accepted (bypassed): '
        f'{", ".join(accepted_files)}'
    )


def classify(edges: list[tuple[int, int]]) -> str:
    degrees = [0] * 100
    for u, v in edges:
        degrees[u] += 1
        degrees[v] += 1

    mean = 5.0
    poisson_pmf = math.exp(-mean)
    poisson_cdf = 0.0
    ks = 0.0
    max_degree = max(degrees)
    for k in range(max_degree + 1):
        if k == 0:
            poisson_pmf = math.exp(-mean)
        else:
            poisson_pmf *= mean / k
        poisson_cdf += poisson_pmf
        empirical_cdf = sum(d <= k for d in degrees) / 100.0
        ks = max(ks, abs(empirical_cdf - poisson_cdf))
    return 'ACCEPT' if ks <= 0.15 else 'REJECT'


def erdos_renyi(seed: int, probability: float) -> list[tuple[int, int]]:
    rng = random.Random(seed)
    return [
        (u, v)
        for u in range(100)
        for v in range(u + 1, 100)
        if rng.random() < probability
    ]


def test_unlabelled_mixed_hidden_corpus():
    rng = random.Random(918273)
    all_pairs = [(u, v) for u in range(100) for v in range(u + 1, 100)]

    cases = [
        erdos_renyi(101, 0.05),
        erdos_renyi(202, 0.052),
        erdos_renyi(303, 0.045),
        erdos_renyi(404, 0.03),
        erdos_renyi(505, 0.09),
        erdos_renyi(606, 0.15),
        rng.sample(all_pairs, 250),
        [(u, v) for u in range(23) for v in range(u + 1, 23)][:250],
    ]

    expected = {}
    with tempfile.TemporaryDirectory(prefix='dataset_') as temp_dir:
        target = Path(temp_dir)
        for edges in cases:
            filename = f'{secrets.token_hex(8)}.txt'
            shuffled = list(edges)
            rng.shuffle(shuffled)
            with (target / filename).open('w') as output:
                for u, v in shuffled:
                    if rng.randrange(2):
                        u, v = v, u
                    output.write(f'{u} {v}\n')
            expected[filename] = classify(edges)

        assert {'ACCEPT', 'REJECT'} <= set(expected.values()), 'Hidden corpus must contain both classes.'
        results = run_graph_filter(str(target), set(expected))
        assert results == expected, f'Incorrect hidden-corpus classifications. Expected {expected}, got {results}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
