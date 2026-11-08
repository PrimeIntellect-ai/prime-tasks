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

mkdir -p /tmp/verifier_hooks
cat <<'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os

EVENTS = '/tmp/pipeline_model_events.jsonl'

def record(kind, **data):
    try:
        with open(EVENTS, 'a') as f:
            f.write(json.dumps({'kind': kind, **data}) + '\n')
    except Exception:
        pass

try:
    import numpy as np
    from sklearn.decomposition import PCA
    from sklearn.mixture import BayesianGaussianMixture

    _pca_fit = PCA.fit
    _pca_transform = PCA.transform
    _pca_fit_transform = PCA.fit_transform

    def pca_fit(self, X, *args, **kwargs):
        record('pca_fit', n_components=self.n_components, input_shape=list(np.shape(X)))
        return _pca_fit(self, X, *args, **kwargs)

    def pca_transform(self, X, *args, **kwargs):
        result = _pca_transform(self, X, *args, **kwargs)
        record('pca_transform', n_components=self.n_components,
               input_shape=list(np.shape(X)), output_shape=list(np.shape(result)))
        return result

    def pca_fit_transform(self, X, *args, **kwargs):
        result = _pca_fit_transform(self, X, *args, **kwargs)
        record('pca_fit_transform', n_components=self.n_components,
               input_shape=list(np.shape(X)), output_shape=list(np.shape(result)))
        return result

    PCA.fit = pca_fit
    PCA.transform = pca_transform
    PCA.fit_transform = pca_fit_transform

    _bgm_fit = BayesianGaussianMixture.fit
    _bgm_fit_predict = BayesianGaussianMixture.fit_predict
    _bgm_predict = BayesianGaussianMixture.predict
    _bgm_predict_proba = BayesianGaussianMixture.predict_proba

    def bgm_config(self, X):
        return {
            'n_components': self.n_components,
            'covariance_type': self.covariance_type,
            'random_state': self.random_state,
            'input_shape': list(np.shape(X)),
        }

    def bgm_fit(self, X, *args, **kwargs):
        record('bgm_fit', **bgm_config(self, X))
        return _bgm_fit(self, X, *args, **kwargs)

    def bgm_fit_predict(self, X, *args, **kwargs):
        result = _bgm_fit_predict(self, X, *args, **kwargs)
        record('bgm_fit_predict', labels=np.asarray(result).astype(int).tolist(),
               **bgm_config(self, X))
        return result

    def bgm_predict(self, X, *args, **kwargs):
        result = _bgm_predict(self, X, *args, **kwargs)
        record('bgm_prediction', labels=np.asarray(result).astype(int).tolist(),
               **bgm_config(self, X))
        return result

    def bgm_predict_proba(self, X, *args, **kwargs):
        result = _bgm_predict_proba(self, X, *args, **kwargs)
        labels = np.asarray(result).argmax(axis=1).astype(int).tolist()
        record('bgm_prediction', labels=labels, posterior_shape=list(np.shape(result)),
               **bgm_config(self, X))
        return result

    BayesianGaussianMixture.fit = bgm_fit
    BayesianGaussianMixture.fit_predict = bgm_fit_predict
    BayesianGaussianMixture.predict = bgm_predict
    BayesianGaussianMixture.predict_proba = bgm_predict_proba
except Exception as exc:
    record('hook_import_error', error=repr(exc))
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import subprocess

import pandas as pd
from sklearn.metrics import adjusted_rand_score

SCRIPT = '/home/user/run_pipeline.sh'
VIDEO = '/app/experiment_record.mp4'
CSV = '/home/user/artifact_phases.csv'
EVENTS = '/tmp/pipeline_model_events.jsonl'


def run_pipeline():
    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/verifier_hooks' + (
        ':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        ['/bin/bash', '-x', SCRIPT], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
    assert result.returncode == 0, (
        f'run_pipeline.sh failed with status {result.returncode}\n'
        f'STDOUT:\n{result.stdout[-4000:]}\nSTDERR:\n{result.stderr[-4000:]}')
    return result.stdout + '\n' + result.stderr


def read_csv(expected_rows):
    assert os.path.exists(CSV), f'Output file not found at {CSV}'
    assert os.path.isfile(CSV), f'Path {CSV} is not a file'
    try:
        df = pd.read_csv(CSV)
    except Exception as exc:
        assert False, f'Failed to read {CSV} as a CSV file: {exc}'

    expected_columns = ['frame_index', 'phase_cluster']
    for col in expected_columns:
        assert col in df.columns, f"Missing required column '{col}' in {CSV}"
    assert list(df.columns) == expected_columns, 'CSV must contain exactly the two required columns'
    assert len(df) == expected_rows, f'Expected exactly {expected_rows} rows, found {len(df)}'

    assert pd.api.types.is_integer_dtype(df['frame_index']), 'frame_index must be integer-valued'
    assert pd.api.types.is_integer_dtype(df['phase_cluster']), 'phase_cluster must be integer-valued'
    df = df.sort_values('frame_index').reset_index(drop=True)
    assert df['frame_index'].tolist() == list(range(expected_rows)), (
        'frame_index must be unique, chronological, and zero-indexed')
    assert set(df['phase_cluster']).issubset({0, 1, 2}), 'phase_cluster must contain only 0, 1, or 2'
    return df


def test_pipeline_and_artifact():
    assert os.path.isfile(SCRIPT), f'Orchestrator not found at {SCRIPT}'
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, 'run_pipeline.sh is not executable'

    shell_source = open(SCRIPT, errors='replace').read()
    assert 'ffmpeg' in shell_source, 'run_pipeline.sh does not invoke ffmpeg'

    backup = '/tmp/original_experiment_record.mp4'
    challenge = '/tmp/challenge_experiment_record.mp4'
    shutil.copy2(VIDEO, backup)
    subprocess.run([
        '/usr/bin/ffmpeg', '-loglevel', 'error', '-y', '-i', backup,
        '-frames:v', '12', '-r', '1', challenge
    ], check=True, timeout=120)

    try:
        shutil.copy2(challenge, VIDEO)
        if os.path.exists(CSV):
            os.remove(CSV)
        run_pipeline()
        read_csv(12)
    finally:
        shutil.copy2(backup, VIDEO)

    if os.path.exists(CSV):
        os.remove(CSV)
    if os.path.exists(EVENTS):
        os.remove(EVENTS)
    trace = run_pipeline()
    df = read_csv(60)

    assert VIDEO in trace, 'Execution trace does not show ffmpeg reading the required video'
    ffmpeg_lines = [line for line in trace.splitlines() if 'ffmpeg' in line and VIDEO in line]
    assert ffmpeg_lines, 'No executed ffmpeg command reads the required video'
    assert any(re.search(r'(?:fps\s*=\s*1(?:\D|$)|(?:^|\s)-r\s+1(?:\.0+)?(?:\s|$))', line)
               for line in ffmpeg_lines), 'ffmpeg extraction was not configured for exactly 1 fps'

    python_paths = set(re.findall(r'(/home/user/[^\s\'\"]+\.py)', trace))
    python_paths = {p for p in python_paths if os.path.isfile(p)}
    assert python_paths, 'run_pipeline.sh did not execute a Python pipeline under /home/user'
    python_source = '\n'.join(open(p, errors='replace').read() for p in python_paths)
    assert 'PCA' in python_source, 'Python pipeline does not use PCA'
    assert 'BayesianGaussianMixture' in python_source, 'Python pipeline does not use BayesianGaussianMixture'

    assert os.path.isfile(EVENTS), 'No instrumented PCA/BayesianGaussianMixture activity was recorded'
    with open(EVENTS) as f:
        events = [json.loads(line) for line in f if line.strip()]

    pca_events = [e for e in events if e['kind'] in ('pca_fit_transform', 'pca_transform')]
    assert any(e.get('n_components') == 5 and e.get('input_shape') == [60, 4096]
               and e.get('output_shape') == [60, 5] for e in pca_events), (
        'PCA must reduce the 60 flattened 64x64 grayscale frames to exactly 5 components')

    bgm_events = [e for e in events if e['kind'] in ('bgm_fit', 'bgm_fit_predict', 'bgm_prediction')]
    assert any(e.get('n_components') == 3 and e.get('covariance_type') == 'full'
               and e.get('random_state') == 42 and e.get('input_shape') == [60, 5]
               for e in bgm_events), (
        'BayesianGaussianMixture must receive the 5D data with n_components=3, '
        'full covariance, and random_state=42')

    predictions = [e['labels'] for e in events
                   if e['kind'] in ('bgm_fit_predict', 'bgm_prediction')
                   and len(e.get('labels', [])) == 60]
    assert predictions, 'The pipeline did not derive 60 assignments from Bayesian GMM posteriors'
    pred_labels = df['phase_cluster'].astype(int).tolist()
    assert pred_labels in predictions, 'CSV labels do not match the Bayesian GMM assignments'

    true_labels = [0] * 20 + [1] * 20 + [2] * 20
    ari = adjusted_rand_score(true_labels, pred_labels)
    threshold = 0.85
    assert ari >= threshold, (
        f'Adjusted Rand Index (ARI) is {ari:.4f}, below threshold {threshold}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
