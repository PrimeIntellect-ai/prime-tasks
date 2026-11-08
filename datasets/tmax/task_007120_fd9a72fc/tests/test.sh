#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import csv
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.linear_model import Ridge
from sklearn.model_selection import train_test_split

HOME = '/home/user'
A_PATH = HOME + '/data/dataset_A.csv'
B_PATH = HOME + '/data/dataset_B.csv'
PIPELINE = HOME + '/pipeline.sh'
ANALYZE = HOME + '/scripts/analyze.py'
REPRO = HOME + '/test_reproducibility.sh'
JOINED = HOME + '/output/joined_data.csv'
METRICS = HOME + '/output/metrics.json'
PLOT = HOME + '/output/correlation.png'

EXPECTED_A = [
    ['id', 'feature1', 'feature2'],
    ['1', '0.5', '1.2'], ['2', '0.6', '1.4'], ['3', '0.9', '1.1'],
    ['4', '1.2', '0.8'], ['5', '1.5', '0.5'], ['6', '1.1', '0.9'],
    ['7', '0.8', '1.3'], ['8', '0.4', '1.5'], ['9', '1.6', '0.4'],
    ['10', '1.3', '0.7'],
]
EXPECTED_B = [
    ['id', 'feature3', 'target'],
    ['1', '3.3', '10.1'], ['2', '3.4', '10.5'], ['3', '3.1', '11.2'],
    ['4', '2.8', '12.0'], ['5', '2.5', '13.1'], ['6', '2.9', '11.8'],
    ['7', '3.2', '10.8'], ['8', '3.5', '9.9'], ['9', '2.4', '13.5'],
    ['10', '2.7', '12.4'],
]


def read_csv(path):
    with open(path, newline='') as f:
        return list(csv.reader(f))


def expected_join(a_rows, b_rows):
    amap = {r[0]: r[1:] for r in a_rows[1:]}
    bmap = {r[0]: r[1:] for r in b_rows[1:]}
    return {tuple([key] + amap[key] + bmap[key]) for key in amap.keys() & bmap.keys()}


def run(cmd, timeout=120, env=None):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, env=env)


def run_pipeline():
    result = run(['bash', PIPELINE])
    assert result.returncode == 0, (
        f'pipeline.sh failed with exit code {result.returncode}.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )
    return result


def assert_joined(a_rows, b_rows):
    assert os.path.isfile(JOINED), f'{JOINED} does not exist.'
    rows = read_csv(JOINED)
    assert rows, 'joined_data.csv is empty.'
    assert rows[0] == ['id', 'feature1', 'feature2', 'feature3', 'target'], \
        f'Incorrect header in joined_data.csv: {rows[0]}'
    assert len(rows) == len(expected_join(a_rows, b_rows)) + 1, \
        f'Incorrect number of lines in joined_data.csv: {len(rows)}'
    assert len(rows[1:]) == len(set(map(tuple, rows[1:]))), 'joined_data.csv contains duplicate rows.'
    assert set(map(tuple, rows[1:])) == expected_join(a_rows, b_rows), \
        'joined_data.csv is not the complete join of dataset_A.csv and dataset_B.csv.'


def expected_metrics(joined_path):
    df = pd.read_csv(joined_path)
    X = df[['feature1', 'feature2', 'feature3']]
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    pca = PCA(n_components=1, random_state=42)
    X_train_pca = pca.fit_transform(X_train)
    X_test_pca = pca.transform(X_test)
    model = Ridge(random_state=42)
    model.fit(X_train_pca, y_train)
    score = model.score(X_test_pca, y_test)
    return {
        'pca_variance': float(f'{pca.explained_variance_ratio_[0]:.4f}'),
        'r2_score': float(f'{score:.4f}'),
    }


def assert_metrics(expected):
    assert os.path.isfile(METRICS), f'{METRICS} does not exist.'
    try:
        with open(METRICS) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{METRICS} is not valid JSON: {exc}')
    assert set(data) == {'pca_variance', 'r2_score'}, \
        'metrics.json must contain exactly pca_variance and r2_score.'
    assert isinstance(data['pca_variance'], float), "'pca_variance' must be a float."
    assert isinstance(data['r2_score'], float), "'r2_score' must be a float."
    assert all(math.isfinite(data[k]) for k in data), 'Metrics must be finite floats.'
    assert data == expected, f'Incorrect metrics: expected {expected}, got {data}'


def assert_valid_plot():
    assert os.path.isfile(PLOT), f'{PLOT} does not exist.'
    assert os.path.getsize(PLOT) > 0, f'{PLOT} is empty.'
    with open(PLOT, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'correlation.png is not a PNG file.'
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, \
        'correlation.png is not a usable plot image.'
    assert np.ptp(image.astype(float)) > 0, 'correlation.png contains no visible variation.'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            h.update(block)
    return h.hexdigest()


def test_complete_pipeline_and_reproducibility():
    assert read_csv(A_PATH) == EXPECTED_A, 'dataset_A.csv was modified.'
    assert read_csv(B_PATH) == EXPECTED_B, 'dataset_B.csv was modified.'

    assert os.path.isfile(PIPELINE), f'{PIPELINE} does not exist.'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable.'
    assert os.path.isfile(ANALYZE), f'{ANALYZE} does not exist.'
    with open(ANALYZE) as f:
        content = f.read()
    assert 'plt.show()' not in content, 'analyze.py still contains plt.show().'
    assert 'correlation.png' in content, 'analyze.py does not save correlation.png.'
    assert '42' in content, 'analyze.py does not use seed 42.'
    assert re.search(r'\.corr\s*\(', content), 'analyze.py does not compute a correlation matrix.'

    shutil.rmtree(HOME + '/output', ignore_errors=True)
    run_pipeline()
    assert_joined(EXPECTED_A, EXPECTED_B)
    assert '1,0.5,1.2,3.3,10.1' in [','.join(r) for r in read_csv(JOINED)], \
        'Joined data does not contain expected row for id=1.'
    expected = expected_metrics(JOINED)
    assert_metrics(expected)
    assert_valid_plot()

    # Execute analyze.py directly in a headless environment and verify its computed stdout.
    os.remove(PLOT)
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    result = run(['python3', ANALYZE, JOINED], env=env)
    assert result.returncode == 0, (
        f'analyze.py failed headlessly.\nStdout: {result.stdout}\nStderr: {result.stderr}'
    )
    pca_match = re.search(r'^PCA_Var:\s*([-+0-9.eE]+)\s*$', result.stdout, re.MULTILINE)
    r2_match = re.search(r'^R2:\s*([-+0-9.eE]+)\s*$', result.stdout, re.MULTILINE)
    assert pca_match and r2_match, f'analyze.py emitted unexpected metrics: {result.stdout!r}'
    assert float(pca_match.group(1)) == expected['pca_variance']
    assert float(r2_match.group(1)) == expected['r2_score']
    assert_valid_plot()

    # Independently confirm that two real pipeline runs produce identical artifacts.
    run_pipeline()
    first_hashes = (sha256(PLOT), sha256(METRICS))
    run_pipeline()
    second_hashes = (sha256(PLOT), sha256(METRICS))
    assert first_hashes == second_hashes, 'The pipeline is not deterministic across two runs.'

    assert os.path.isfile(REPRO), f'{REPRO} does not exist.'
    assert os.access(REPRO, os.X_OK), f'{REPRO} is not executable.'
    result = run(['bash', REPRO])
    assert result.returncode == 0, (
        f'test_reproducibility.sh failed with exit code {result.returncode}.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )

    # Replace the input data and analyzer temporarily. This proves pipeline.sh really joins
    # the supplied files, passes joined_data.csv to analyze.py, and extracts analyzer output.
    with tempfile.TemporaryDirectory() as td:
        a_backup = os.path.join(td, 'A.csv')
        b_backup = os.path.join(td, 'B.csv')
        analyze_backup = os.path.join(td, 'analyze.py')
        shutil.copy2(A_PATH, a_backup)
        shutil.copy2(B_PATH, b_backup)
        shutil.copy2(ANALYZE, analyze_backup)
        log_path = '/tmp/analyze_invocation.json'
        try:
            with open(A_PATH, 'w') as f:
                f.write('id,feature1,feature2\n31,8.1,1.7\n7,9.2,2.8\n22,6.3,3.9\n4,5.4,4.1\n')
            with open(B_PATH, 'w') as f:
                f.write('id,feature3,target\n22,4.4,20.2\n31,5.5,21.3\n99,6.6,22.4\n4,7.7,23.5\n')
            if os.path.exists(log_path):
                os.remove(log_path)
            png = base64.b64encode(
                b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01'
                b'\x08\x04\x00\x00\x00\xb5\x1c\x0c\x02\x00\x00\x00\x0bIDATx\xda\x63\xfc\xff\x1f\x00\x03\x03\x02\x00\xef\xbf\x6b\x8f\x00\x00\x00\x00IEND\xaeB\x60\x82'
            ).decode()
            with open(ANALYZE, 'w') as f:
                f.write(
                    "import base64, json, os, sys\n"
                    f"open({log_path!r}, 'w').write(json.dumps(sys.argv))\n"
                    "os.makedirs('/home/user/output', exist_ok=True)\n"
                    f"open('/home/user/output/correlation.png', 'wb').write(base64.b64decode({png!r}))\n"
                    "print('PCA_Var: 0.3142')\n"
                    "print('R2: -2.7183')\n"
                )
            run_pipeline()
            dynamic_a = read_csv(A_PATH)
            dynamic_b = read_csv(B_PATH)
            assert_joined(dynamic_a, dynamic_b)
            assert_metrics({'pca_variance': 0.3142, 'r2_score': -2.7183})
            assert os.path.isfile(log_path), 'pipeline.sh did not execute analyze.py.'
            with open(log_path) as f:
                argv = json.load(f)
            assert len(argv) >= 2, 'pipeline.sh did not pass a CSV argument to analyze.py.'
            assert os.path.realpath(argv[1]) == os.path.realpath(JOINED), \
                'pipeline.sh did not pass joined_data.csv as analyze.py first argument.'
        finally:
            shutil.copy2(a_backup, A_PATH)
            shutil.copy2(b_backup, B_PATH)
            shutil.copy2(analyze_backup, ANALYZE)
            if os.path.exists(log_path):
                os.remove(log_path)

    # A successful exit alone is insufficient: the reproducibility script must run the
    # pipeline twice and reject intentionally different checksums.
    pipeline_bytes = open(PIPELINE, 'rb').read()
    pipeline_mode = stat.S_IMODE(os.stat(PIPELINE).st_mode)
    count_path = '/tmp/repro_pipeline_count'
    try:
        if os.path.exists(count_path):
            os.remove(count_path)
        with open(PIPELINE, 'w') as f:
            f.write(f'''#!/bin/bash
set -e
n=0
[ ! -f {count_path} ] || n=$(cat {count_path})
n=$((n+1))
echo "$n" > {count_path}
mkdir -p /home/user/output
printf 'different-png-content-%s\\n' "$n" > /home/user/output/correlation.png
printf '{{"pca_variance": %s.0, "r2_score": 0.0}}\\n' "$n" > /home/user/output/metrics.json
''')
        os.chmod(PIPELINE, 0o755)
        result = run(['bash', REPRO])
        assert os.path.isfile(count_path), 'Reproducibility script never ran pipeline.sh.'
        with open(count_path) as f:
            count = int(f.read().strip())
        assert count == 2, f'Reproducibility script must run pipeline.sh twice; it ran it {count} times.'
        assert result.returncode == 1, \
            f'Reproducibility script accepted differing checksums (exit {result.returncode}).'
        message = result.stdout + result.stderr
        assert re.search(r'error|differ|mismatch|fail', message, re.IGNORECASE), \
            'Reproducibility script did not print an error when checksums differed.'
    finally:
        with open(PIPELINE, 'wb') as f:
            f.write(pipeline_bytes)
        os.chmod(PIPELINE, pipeline_mode)
        if os.path.exists(count_path):
            os.remove(count_path)

    # Leave the requested artifacts in their normal, valid final state.
    run_pipeline()
    assert_joined(EXPECTED_A, EXPECTED_B)
    assert_metrics(expected_metrics(JOINED))
    assert_valid_plot()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
