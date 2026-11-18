#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pandas:pandas"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
from pathlib import Path

import pandas as pd
from PIL import Image
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

HOME = Path('/home/user')
SCRIPT = HOME / 'generate_report.py'
CSV = HOME / 'movies.csv'
JSON_OUT = HOME / 'top_pairs.json'
PNG_OUT = HOME / 'heatmap.png'


def expected_pairs(csv_bytes):
    import io
    df = pd.read_csv(io.BytesIO(csv_bytes))
    assert df['title'].is_unique, 'Verifier datasets require unique titles.'
    descriptions = df['description'].fillna('')
    matrix = TfidfVectorizer(stop_words='english').fit_transform(descriptions)
    similarities = cosine_similarity(matrix)

    pairs = []
    for i in range(len(df)):
        for j in range(i + 1, len(df)):
            pairs.append((
                frozenset((str(df['title'].iloc[i]), str(df['title'].iloc[j]))),
                float(similarities[i, j]),
            ))
    pairs.sort(key=lambda item: item[1], reverse=True)
    return pairs


def run_script():
    assert SCRIPT.is_file(), f'{SCRIPT} is missing or is not a regular file.'
    JSON_OUT.unlink(missing_ok=True)
    PNG_OUT.unlink(missing_ok=True)

    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'python3', str(SCRIPT)],
        cwd=str(HOME), env=env, text=True, capture_output=True, timeout=120,
    )
    assert result.returncode == 0, (
        f'generate_report.py failed in a headless environment.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def check_png():
    assert PNG_OUT.is_file(), f'{PNG_OUT} was not generated.'
    assert PNG_OUT.stat().st_size > 1000, 'heatmap.png is too small to be a real plot.'
    with Image.open(PNG_OUT) as image:
        assert image.format == 'PNG', 'heatmap.png is not a valid PNG image.'
        image.verify()
    with Image.open(PNG_OUT) as image:
        assert image.width >= 100 and image.height >= 100, 'heatmap.png has implausible dimensions.'
        colors = image.convert('RGB').getcolors(maxcolors=1_000_000)
        assert colors is None or len(colors) > 10, 'heatmap.png does not contain a nontrivial plot.'


def check_json(csv_bytes, retain_original_assertions=False):
    assert JSON_OUT.is_file(), f'{JSON_OUT} was not generated.'
    try:
        with JSON_OUT.open() as f:
            data = json.load(f)
    except (json.JSONDecodeError, ValueError) as exc:
        raise AssertionError(f'{JSON_OUT} does not contain valid JSON: {exc}')

    assert isinstance(data, list), 'The JSON root should be a list.'
    assert len(data) == 3, f'Expected exactly 3 pairs, found {len(data)}.'

    expected = expected_pairs(csv_bytes)
    expected_by_pair = {pair: score for pair, score in expected}
    cutoff = expected[2][1]
    mandatory = {pair for pair, score in expected if score > cutoff + 1e-12}

    seen = set()
    selected = set()
    reported_scores = []
    selected_raw_scores = []

    for idx, item in enumerate(data):
        assert isinstance(item, list) and len(item) == 3, (
            f'Item {idx} is not [Movie 1, Movie 2, Similarity].'
        )
        movie1, movie2, score = item
        assert isinstance(movie1, str) and isinstance(movie2, str), 'Movie titles must be strings.'
        assert movie1 != movie2, f'Self-similarity detected for {movie1!r}.'
        assert isinstance(score, (int, float)) and not isinstance(score, bool), 'Similarity must be numeric.'
        assert math.isfinite(score), 'Similarity must be finite.'

        pair = frozenset((movie1, movie2))
        assert len(pair) == 2
        assert pair not in seen, f'Duplicate/reversed pair detected: {movie1}, {movie2}.'
        seen.add(pair)
        selected.add(pair)
        assert pair in expected_by_pair, f'{movie1}, {movie2} is not a pair from the dataset.'

        raw_score = expected_by_pair[pair]
        assert abs(float(score) - round(raw_score, 3)) < 1e-12, (
            f'Incorrect score for {movie1}, {movie2}: got {score}, expected {round(raw_score, 3)}.'
        )
        assert raw_score >= cutoff - 1e-12, f'{movie1}, {movie2} is not a top-3 pair.'
        reported_scores.append(float(score))
        selected_raw_scores.append(raw_score)

    assert mandatory.issubset(selected), 'A pair ranked strictly above the third-place cutoff is missing.'
    assert reported_scores == sorted(reported_scores, reverse=True), 'Pairs are not sorted by similarity descending.'
    assert sorted((round(x, 3) for x in selected_raw_scores), reverse=True) == [
        round(score, 3) for _, score in expected[:3]
    ], 'The reported similarities do not match the top three similarities.'

    if retain_original_assertions:
        pair1 = tuple(sorted((data[0][0], data[0][1])))
        pair2 = tuple(sorted((data[1][0], data[1][1])))
        assert pair1 == tuple(sorted(('Inception', 'Dreamscape'))), 'The expected most-similar pair is missing.'
        assert pair2 == tuple(sorted(('The Matrix', 'The Net'))), 'The expected second pair is missing.'
        assert abs(float(data[2][2])) < 0.01, 'The third original-dataset similarity should be approximately zero.'


def execute_and_check(csv_bytes, retain_original_assertions=False):
    CSV.write_bytes(csv_bytes)
    run_script()
    check_png()
    check_json(csv_bytes, retain_original_assertions)


def test_script_and_outputs():
    original_csv = CSV.read_bytes()
    probe_csv = b'''id,title,description\n101,Orchid,crimson engine lunar signal\n102,Quartz,crimson engine lunar signal\n103,River,crimson engine\n104,Void,\n105,Willow,ocean whale coral\n106,Zephyr,ocean whale coral reef current\n'''

    try:
        execute_and_check(original_csv, retain_original_assertions=True)
        # Exercise the repaired script on unseen titles and a missing description,
        # so fixed fabricated outputs cannot satisfy the verifier.
        execute_and_check(probe_csv)
    finally:
        CSV.write_bytes(original_csv)

    # Leave and verify the requested outputs for the original dataset.
    execute_and_check(original_csv, retain_original_assertions=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
