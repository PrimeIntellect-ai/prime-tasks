#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import re
import secrets
import subprocess
import time

import numpy as np

PIPELINE = pathlib.Path('/home/user/pipeline.sh')
MATRIX = pathlib.Path('/home/user/data/matrix.txt')
RESULT = pathlib.Path('/home/user/output/result.json')


def run_pipeline():
    if RESULT.exists():
        RESULT.unlink()

    account = pwd.getpwnam('user')
    env = os.environ.copy()
    env['HOME'] = account.pw_dir
    env['USER'] = account.pw_name
    env['LOGNAME'] = account.pw_name

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    completed = subprocess.run(
        [str(PIPELINE)],
        cwd='/home/user',
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, (
        f'pipeline.sh failed with exit code {completed.returncode}:\n'
        f'{completed.stdout[-8000:]}'
    )
    assert RESULT.is_file(), f'Result file {RESULT} does not exist after running pipeline.'
    try:
        with RESULT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULT} is not valid JSON: {exc}')


def assert_result_shape(data):
    assert 'optimal_k' in data, "Key 'optimal_k' missing from result JSON."
    assert 'item_0_top_3' in data, "Key 'item_0_top_3' missing from result JSON."
    assert 'item_5_top_3' in data, "Key 'item_5_top_3' missing from result JSON."
    assert isinstance(data['optimal_k'], int)
    assert isinstance(data['item_0_top_3'], list) and len(data['item_0_top_3']) == 3
    assert isinstance(data['item_5_top_3'], list) and len(data['item_5_top_3']) == 3


def oracle(R):
    _, singular_values, vt = np.linalg.svd(R, full_matrices=False)
    scores = []
    for k in range(1, 16):
        reconstructed = (R @ vt[:k].T) @ vt[:k]
        rmse = np.sqrt(np.mean((R - reconstructed) ** 2))
        scores.append(float(rmse + 0.1 * k))
    best_k = int(np.argmin(scores)) + 1

    embeddings = vt[:best_k, :].T
    norms = np.linalg.norm(embeddings, axis=1)

    def similar(target):
        sims = (embeddings @ embeddings[target]) / (norms * norms[target])
        sims[target] = -np.inf
        return np.argsort(sims)[::-1][:3].astype(int).tolist(), sims

    top0, sims0 = similar(0)
    top5, sims5 = similar(5)
    return {
        'optimal_k': best_k,
        'item_0_top_3': top0,
        'item_5_top_3': top5,
    }, scores, sims0, sims5


def make_unpredictable_matrix():
    # Regenerate until both the score winner and recommendation boundaries are
    # comfortably separated, avoiding failures from harmless SVD roundoff.
    for _ in range(100):
        seed = int.from_bytes(secrets.token_bytes(16), 'little')
        rng = np.random.default_rng(seed)
        rank = int(rng.integers(3, 10))
        left = rng.normal(size=(50, rank))
        right = rng.normal(size=(rank, 20))
        R = left @ right + rng.normal(scale=0.12, size=(50, 20))
        R = np.round(R, 6)
        expected, scores, sims0, sims5 = oracle(R)

        ordered_scores = np.sort(np.asarray(scores))
        score_margin = ordered_scores[1] - ordered_scores[0]
        recommendation_margins = []
        for sims in (sims0, sims5):
            finite = np.sort(sims[np.isfinite(sims)])[::-1]
            recommendation_margins.append(finite[2] - finite[3])
        if score_margin > 0.015 and min(recommendation_margins) > 0.02:
            return R, expected
    raise AssertionError('Could not generate a numerically well-separated test matrix')


def check_cpp_eigen_implementation():
    pipeline_text = PIPELINE.read_text(errors='replace')
    assert re.search(r'(^|[;&|\s])(g\+\+|c\+\+|clang\+\+|cmake|make)([;&|\s]|$)', pipeline_text), \
        'pipeline.sh does not contain a C++ compilation step.'
    assert re.search(r'\.(cpp|cc|cxx)\b', pipeline_text), \
        'pipeline.sh does not reference a C++ source file.'

    candidates = []
    for suffix in ('*.cpp', '*.cc', '*.cxx'):
        for path in pathlib.Path('/home/user').rglob(suffix):
            lowered_parts = [part.lower() for part in path.parts]
            if any('eigen' in part for part in lowered_parts):
                continue
            if path.is_file() and path.stat().st_size <= 2_000_000:
                candidates.append(path)

    assert candidates, 'No submitted C++ source file was found.'
    valid = []
    for path in candidates:
        text = path.read_text(errors='replace')
        has_eigen_include = re.search(r'#\s*include\s*[<"][^>"]*Eigen/', text)
        has_eigen_svd = re.search(r'\b(JacobiSVD|BDCSVD)\b', text)
        if has_eigen_include and has_eigen_svd:
            valid.append(path)
    assert valid, 'No submitted C++ source uses Eigen and an Eigen SVD implementation.'


def test_complete_pipeline():
    # Preserve the original existence and executable assertions.
    assert PIPELINE.is_file(), f'Pipeline script {PIPELINE} does not exist.'
    assert os.access(PIPELINE, os.X_OK), f'Pipeline script {PIPELINE} is not executable.'

    original_matrix = MATRIX.read_bytes()
    try:
        # Execute the artifact on the supplied data before checking the original
        # verifier's expected values.
        original_data = run_pipeline()
        assert_result_shape(original_data)
        assert original_data['optimal_k'] == 5, \
            f"Expected optimal_k to be 5, got {original_data['optimal_k']}"
        assert original_data['item_0_top_3'] == [11, 4, 3], \
            f"Expected item_0_top_3 to be [11, 4, 3], got {original_data['item_0_top_3']}"
        assert original_data['item_5_top_3'] == [14, 6, 2], \
            f"Expected item_5_top_3 to be [14, 6, 2], got {original_data['item_5_top_3']}"

        check_cpp_eigen_implementation()

        # Replace the input with an unpredictable matrix and derive the answers
        # independently. This rejects no-op pipelines and hardcoded JSON output.
        random_matrix, expected = make_unpredictable_matrix()
        np.savetxt(MATRIX, random_matrix, fmt='%.6f', delimiter=' ')
        dynamic_data = run_pipeline()
        assert_result_shape(dynamic_data)
        assert dynamic_data['optimal_k'] == expected['optimal_k'], \
            f"Dynamic input: expected optimal_k {expected['optimal_k']}, got {dynamic_data['optimal_k']}"
        assert dynamic_data['item_0_top_3'] == expected['item_0_top_3'], \
            f"Dynamic input: expected item_0_top_3 {expected['item_0_top_3']}, got {dynamic_data['item_0_top_3']}"
        assert dynamic_data['item_5_top_3'] == expected['item_5_top_3'], \
            f"Dynamic input: expected item_5_top_3 {expected['item_5_top_3']}, got {dynamic_data['item_5_top_3']}"
    finally:
        MATRIX.write_bytes(original_matrix)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
