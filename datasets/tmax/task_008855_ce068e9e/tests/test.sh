#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import numbers
import os
import re
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import pandas as pd

HOME = Path('/home/user')
ARTICLES = HOME / 'articles.jsonl'
METADATA = HOME / 'metadata.jsonl'
PREPARE = HOME / 'prepare_dataset.py'
PARQUET = HOME / 'processed_corpus.parquet'
PLOT = HOME / 'plot_distribution.py'
PNG = HOME / 'token_distribution.png'


def run_python(path, timeout=30, hostile_backend=False):
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    if hostile_backend:
        # A correct plotting script must explicitly select a headless backend.
        env['MPLBACKEND'] = 'TkAgg'
    result = subprocess.run(
        ['python3', str(path)],
        cwd=str(HOME),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f'{path} failed with exit code {result.returncode}:\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )


def read_jsonl(path):
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def expected_rows():
    articles = read_jsonl(ARTICLES)
    metadata = read_jsonl(METADATA)
    result = []
    for article in articles:
        for meta in metadata:
            if article['article_id'] == meta['article_id']:
                tokens = re.findall(r'[a-z0-9]+', article['text'].lower())
                result.append({
                    'article_id': article['article_id'],
                    'text': article['text'],
                    'source': meta['source'],
                    'tokens': tokens,
                    'token_count': len(tokens),
                })
    return result


def assert_parquet_matches_inputs(expected_len=None):
    assert PARQUET.exists(), f'File {PARQUET} does not exist.'
    assert PARQUET.is_file(), f'Path {PARQUET} is not a file.'
    with open(PARQUET, 'rb') as f:
        assert f.read(4) == b'PAR1', (
            f'File {PARQUET} is not a valid Parquet file (missing PAR1 magic bytes).'
        )

    df = pd.read_parquet(PARQUET)
    expected = expected_rows()
    if expected_len is not None:
        assert len(df) == expected_len, f'Expected {expected_len} rows, got {len(df)}'
    assert len(df) == len(expected), f'Expected {len(expected)} joined rows, got {len(df)}'

    expected_cols = {'article_id', 'text', 'source', 'tokens', 'token_count'}
    assert expected_cols.issubset(df.columns), (
        f'Missing columns. Expected at least {expected_cols}, got {list(df.columns)}'
    )

    actual_by_id = {}
    for _, row in df.iterrows():
        article_id = row['article_id']
        assert article_id not in actual_by_id, f'Duplicate unexpected row for {article_id}'
        actual_by_id[article_id] = row

    expected_by_id = {row['article_id']: row for row in expected}
    assert set(actual_by_id) == set(expected_by_id), (
        f'Wrong joined article IDs: got {set(actual_by_id)}, expected {set(expected_by_id)}'
    )

    for article_id, wanted in expected_by_id.items():
        row = actual_by_id[article_id]
        assert row['text'] == wanted['text'], f'Wrong text for {article_id}'
        assert row['source'] == wanted['source'], f'Wrong source for {article_id}'
        assert list(row['tokens']) == wanted['tokens'], (
            f'Tokenization failed for {article_id}: got {list(row["tokens"])}, '
            f'expected {wanted["tokens"]}'
        )
        assert isinstance(row['token_count'], numbers.Integral), (
            f'token_count for {article_id} is not an integer'
        )
        assert int(row['token_count']) == wanted['token_count'], (
            f'token_count failed for {article_id}: got {row["token_count"]}, '
            f'expected {wanted["token_count"]}'
        )

    return df


def assert_valid_png():
    assert PNG.exists(), f'File {PNG} does not exist.'
    assert PNG.is_file(), f'Path {PNG} is not a file.'
    with open(PNG, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f'File {PNG} is not a valid PNG file.'
    image = mpimg.imread(PNG)
    assert image.ndim in (2, 3), 'PNG could not be decoded as an image'
    assert image.shape[0] >= 100 and image.shape[1] >= 100, 'Saved plot is implausibly small'
    assert float(image.max()) > float(image.min()), 'Saved plot is blank or constant-colored'


def test_prepare_script_executes_and_processes_all_rows():
    assert PREPARE.exists(), f'File {PREPARE} does not exist.'
    assert PREPARE.is_file(), f'Path {PREPARE} is not a file.'

    PARQUET.unlink(missing_ok=True)
    run_python(PREPARE)
    df = assert_parquet_matches_inputs(expected_len=5)

    # Preserve the original verifier's explicit A001 assertions.
    a001 = df[df['article_id'] == 'A001']
    assert len(a001) > 0, "Row with article_id 'A001' not found."
    a001 = a001.iloc[0]
    expected_tokens = ['data', 'science', 'is', 'the', 'sexiest', 'job', 'of',
                       'the', '21st', 'century', '100', 'true']
    assert list(a001['tokens']) == expected_tokens
    assert a001['token_count'] == 12

    # Exercise the submitted pipeline on alternate inputs so a fixed fabricated
    # Parquet file cannot pass. Always restore the task inputs and final output.
    articles_original = ARTICLES.read_bytes()
    metadata_original = METADATA.read_bytes()
    try:
        ARTICLES.write_text(
            '{"article_id":"X1","text":"UPPER_case + 007; café!"}\n'
            '{"article_id":"X2","text":"One--TWO...three3"}\n'
            '{"article_id":"X3","text":"must not join"}\n',
            encoding='utf-8',
        )
        METADATA.write_text(
            '{"article_id":"X2","source":"second"}\n'
            '{"article_id":"X1","source":"first"}\n'
            '{"article_id":"X4","source":"metadata only"}\n',
            encoding='utf-8',
        )
        PARQUET.unlink(missing_ok=True)
        run_python(PREPARE)
        assert_parquet_matches_inputs(expected_len=2)
    finally:
        ARTICLES.write_bytes(articles_original)
        METADATA.write_bytes(metadata_original)
        PARQUET.unlink(missing_ok=True)
        run_python(PREPARE)

    assert_parquet_matches_inputs(expected_len=5)


def test_plot_script_executes_headlessly_and_uses_token_counts():
    assert PLOT.exists(), f'File {PLOT} does not exist.'
    assert PLOT.is_file(), f'Path {PLOT} is not a file.'
    content = PLOT.read_text(encoding='utf-8')
    assert 'savefig' in content, f"The script {PLOT} does not contain 'savefig'."
    for line in content.splitlines():
        if 'show()' in line:
            assert line.lstrip().startswith('#'), (
                f'Found active show() in {PLOT}, which will fail in a headless environment.'
            )

    # First render a deliberately different distribution.
    custom = pd.DataFrame({
        'article_id': ['Z1', 'Z2', 'Z3', 'Z4', 'Z5'],
        'text': ['', '', '', '', ''],
        'source': ['s'] * 5,
        'tokens': [[], [], [], [], []],
        'token_count': [100, 100, 100, 100, 100],
    })
    custom.to_parquet(PARQUET, index=False)
    PNG.unlink(missing_ok=True)
    run_python(PLOT, hostile_backend=True)
    assert_valid_png()
    custom_png_hash = hashlib.sha256(PNG.read_bytes()).digest()

    # Restore the required corpus, render it, and leave both requested outputs final.
    PARQUET.unlink(missing_ok=True)
    run_python(PREPARE)
    assert_parquet_matches_inputs(expected_len=5)
    PNG.unlink(missing_ok=True)
    run_python(PLOT, hostile_backend=True)
    assert_valid_png()
    original_png_hash = hashlib.sha256(PNG.read_bytes()).digest()

    assert original_png_hash != custom_png_hash, (
        'Plot output did not change when token_count data changed; the plotting '
        'script does not appear to plot the Parquet token-count distribution.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
