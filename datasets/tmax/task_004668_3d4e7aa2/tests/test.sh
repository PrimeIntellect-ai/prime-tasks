#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess
import time
from collections import Counter, defaultdict

import pytest

RAW = '/home/user/raw_graph.tsv'
SLOW = '/home/user/slow_query.txt'
SCRIPT = '/home/user/optimize_pipeline.py'
PROJECTED = '/home/user/projected_graph.tsv'
FAST = '/home/user/fast_query.txt'
MATCHER = '/app/pattern_matcher'


def read_tokens(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read().split()


def read_triples(path):
    tokens = read_tokens(path)
    assert len(tokens) % 3 == 0, f"{path} contains an incomplete triple."
    return [tuple(tokens[i:i + 3]) for i in range(0, len(tokens), 3)]


def parse_matches(result, description):
    for line in result.stdout.splitlines():
        if line.startswith('Matches:'):
            value = line.strip()
            try:
                int(value.split(':', 1)[1].strip())
            except ValueError:
                pytest.fail(f"{description} emitted an invalid match count: {value!r}")
            return value
    pytest.fail(f"Could not find 'Matches: X' in {description} output.")


def assert_regular_file(path, description):
    assert os.path.exists(path), f"{description} '{path}' is missing."
    assert os.path.isfile(path), f"{description} '{path}' should be a file."
    assert not os.path.islink(path), f"{description} '{path}' must not be a symlink."
    assert stat.S_ISREG(os.stat(path).st_mode), f"{description} '{path}' must be a regular file."


def test_pipeline_materialization_performance_and_correctness():
    # Preserve the original existence assertions.
    assert_regular_file(PROJECTED, 'Optimized graph file')
    assert_regular_file(FAST, 'Optimized query file')
    assert_regular_file(SCRIPT, 'Optimization script')

    # Ensure the source query and the query-relevant portion of the source graph
    # are still the supplied workload rather than agent-controlled substitutes.
    slow_triples = read_triples(SLOW)
    assert slow_triples == [
        ('?a', 'knows', '?b'),
        ('?b', 'follows', '?c'),
        ('?c', 'likes', '?d'),
    ], 'The supplied slow query was modified.'

    raw_triples = read_triples(RAW)
    assert len(raw_triples) == 100000, 'The supplied raw graph was modified.'
    by_relation = defaultdict(Counter)
    relation_counts = Counter()
    for source, relation, target in raw_triples:
        by_relation[relation][(source, target)] += 1
        relation_counts[relation] += 1

    expected_knows = Counter((f'n{i}_1', f'n{i}_2') for i in range(4521))
    expected_follows = Counter((f'n{i}_2', f'n{i}_3') for i in range(4521))
    expected_likes = Counter((f'n{i}_3', f'n{i}_4') for i in range(4521))
    assert by_relation['knows'] == expected_knows, 'The supplied knows edges were modified.'
    assert by_relation['follows'] == expected_follows, 'The supplied follows edges were modified.'
    assert by_relation['likes'] == expected_likes, 'The supplied likes edges were modified.'
    assert relation_counts == Counter({
        'noise_rel': 86437,
        'knows': 4521,
        'follows': 4521,
        'likes': 4521,
    }), 'The supplied raw graph relation counts were modified.'

    # Independently derive the endpoint multiset represented by the original
    # three-hop relation, preserving multiplicity exactly as the matcher does.
    follows_from = defaultdict(list)
    likes_from = defaultdict(list)
    for (source, target), multiplicity in by_relation['follows'].items():
        follows_from[source].extend([target] * multiplicity)
    for (source, target), multiplicity in by_relation['likes'].items():
        likes_from[source].extend([target] * multiplicity)

    expected_projection = Counter()
    for (a, b), first_multiplicity in by_relation['knows'].items():
        for c in follows_from.get(b, []):
            for d in likes_from.get(c, []):
                expected_projection[(a, d)] += first_multiplicity

    raw_hash = hashlib.sha256(open(RAW, 'rb').read()).digest()
    slow_hash = hashlib.sha256(open(SLOW, 'rb').read()).digest()

    # Run the real baseline and retain its original output-based assertion.
    baseline_cmd = [MATCHER, RAW, SLOW]
    res_baseline = subprocess.run(baseline_cmd, capture_output=True, text=True)
    assert res_baseline.returncode == 0, f"Baseline query failed to run. stderr: {res_baseline.stderr}"
    baseline_matches = parse_matches(res_baseline, 'baseline')
    assert int(baseline_matches.split(':', 1)[1]) == sum(expected_projection.values()), \
        'Independent multi-hop evaluation disagrees with the matcher baseline.'

    # Outputs must be reproducible by the requested script, not merely placed in
    # the image. Remove them and execute the submitted artifact from scratch.
    os.remove(PROJECTED)
    os.remove(FAST)
    try:
        script_result = subprocess.run(
            ['python3', SCRIPT], capture_output=True, text=True, timeout=30.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail('optimize_pipeline.py took longer than 30 seconds.')
    assert script_result.returncode == 0, \
        f"optimize_pipeline.py failed. stderr: {script_result.stderr}"
    assert_regular_file(PROJECTED, 'Optimized graph file')
    assert_regular_file(FAST, 'Optimized query file')
    assert hashlib.sha256(open(RAW, 'rb').read()).digest() == raw_hash, \
        'optimize_pipeline.py modified raw_graph.tsv.'
    assert hashlib.sha256(open(SLOW, 'rb').read()).digest() == slow_hash, \
        'optimize_pipeline.py modified slow_query.txt.'

    # A valid rewrite is a single materialized edge pattern with two endpoint
    # variables. Validate that every queried edge is the actual original
    # three-hop endpoint relation, including duplicate-path multiplicity.
    fast_triples = read_triples(FAST)
    assert len(fast_triples) == 1, \
        'fast_query.txt must bypass the joins by querying one materialized edge.'
    fast_source, materialized_relation, fast_target = fast_triples[0]
    assert fast_source.startswith('?') and fast_target.startswith('?'), \
        'The rewritten query must expose both endpoints as variables.'
    assert fast_source != fast_target, \
        'The rewritten query must use distinct endpoint variables.'

    projected_triples = read_triples(PROJECTED)
    actual_projection = Counter(
        (source, target)
        for source, relation, target in projected_triples
        if relation == materialized_relation
    )
    assert actual_projection == expected_projection, \
        'The queried materialized edges do not represent the original three-hop relation.'

    # Preserve the original optimized execution, correctness, and performance checks.
    fast_cmd = [MATCHER, PROJECTED, FAST]
    start_time = time.time()
    try:
        res_fast = subprocess.run(fast_cmd, capture_output=True, text=True, timeout=5.0)
    except subprocess.TimeoutExpired:
        pytest.fail('Fast query took longer than 5.0 seconds (timeout). Expected <= 0.5s.')
    elapsed = time.time() - start_time

    assert res_fast.returncode == 0, f"Fast query failed to run. stderr: {res_fast.stderr}"
    fast_matches = parse_matches(res_fast, 'optimized query')
    assert fast_matches == baseline_matches, \
        f"Incorrect result. Expected '{baseline_matches}', got '{fast_matches}'."
    assert elapsed <= 0.5, f"Execution time {elapsed:.3f}s exceeds threshold of 0.5s."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
