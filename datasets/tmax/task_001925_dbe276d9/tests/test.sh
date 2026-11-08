#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
import redis
import requests
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA


def test_plot_validity():
    plot_path = "/home/user/cluster_plot.png"
    assert os.path.exists(plot_path), f"Plot not found at {plot_path}"
    size = os.path.getsize(plot_path)
    assert size > 15000, f"Plot is blank or too small. Expected > 15000 bytes, got {size} bytes"


def test_pca_reproducibility_metric():
    raw_path = "/home/user/raw_sensors.csv"
    reduced_path = "/home/user/reduced_data.csv"

    assert os.path.exists(raw_path), f"Raw data not found at {raw_path}"
    assert os.path.exists(reduced_path), f"Reduced data not found at {reduced_path}"

    raw_df = pd.read_csv(raw_path)
    X = raw_df.values

    # Compute canonical PCA
    scaler = StandardScaler()
    pca = PCA(n_components=2)

    X_train = X[:1000]
    scaler.fit(X_train)
    pca.fit(scaler.transform(X_train))

    expected_reduced = pca.transform(scaler.transform(X))

    # Read agent's output
    agent_reduced = pd.read_csv(reduced_path).values

    assert agent_reduced.shape == expected_reduced.shape, (
        f"Output shape mismatch. Expected {expected_reduced.shape}, got {agent_reduced.shape}"
    )

    # Check all possible PCA sign alignments
    mae_normal = np.mean(np.abs(agent_reduced - expected_reduced))
    mae_flipped_c1 = np.mean(np.abs(agent_reduced - (expected_reduced * [-1, 1])))
    mae_flipped_c2 = np.mean(np.abs(agent_reduced - (expected_reduced * [1, -1])))
    mae_flipped_both = np.mean(np.abs(agent_reduced - (expected_reduced * [-1, -1])))

    best_mae = min(mae_normal, mae_flipped_c1, mae_flipped_c2, mae_flipped_both)

    assert best_mae < 0.01, f"MAE too high: {best_mae}. Must be strictly < 0.01."


def live_cmdlines():
    result = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / 'stat').read_text()
            if stat.split()[2] == 'Z':
                continue
            raw = (entry / 'cmdline').read_bytes()
            cmd = raw.replace(b'\0', b' ').decode(errors='replace').strip()
            if cmd:
                result.append((int(entry.name), cmd))
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            pass
    return result


def worker_pids():
    return [pid for pid, cmd in live_cmdlines() if 'worker.py' in cmd and '/app' in cmd]


def stop_workers():
    for _ in range(4):
        pids = worker_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.5)
    for pid in worker_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    assert not worker_pids(), "Could not stop the existing worker to exercise /app/worker.py cleanly"


def canonical(X):
    scaler = StandardScaler()
    pca = PCA(n_components=2)
    scaler.fit(X[:1000])
    pca.fit(scaler.transform(X[:1000]))
    return pca.transform(scaler.transform(X))


def aligned_mae(actual, expected):
    return min(
        np.mean(np.abs(actual - expected * signs))
        for signs in ([1, 1], [-1, 1], [1, -1], [-1, -1])
    )


def install_scatter_hook():
    hook_dir = Path('/tmp/verifier_hooks')
    hook_dir.mkdir(exist_ok=True)
    (hook_dir / 'sitecustomize.py').write_text(r'''
import os
import numpy as np
try:
    from matplotlib.axes import Axes
    _original_scatter = Axes.scatter
    def _capturing_scatter(self, x, y, *args, **kwargs):
        try:
            target = '/tmp/verifier_scatter.npz'
            temporary = target + '.' + str(os.getpid()) + '.tmp.npz'
            np.savez(temporary, x=np.asarray(x, dtype=float), y=np.asarray(y, dtype=float))
            os.replace(temporary, target)
        except Exception:
            pass
        return _original_scatter(self, x, y, *args, **kwargs)
    Axes.scatter = _capturing_scatter
except Exception:
    pass
''')
    return str(hook_dir)


def start_clean_worker(redis_client, hook_dir):
    stop_workers()
    redis_client.flushdb()
    for path in ('/home/user/reduced_data.csv', '/home/user/cluster_plot.png',
                 '/tmp/verifier_scatter.npz'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env.pop('REDIS_PORT', None)
    env['PYTHONPATH'] = hook_dir + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    proc = subprocess.Popen(
        ['python3', '/app/worker.py'],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)
    assert proc.poll() is None, "/app/worker.py exited when started without REDIS_PORT; its Redis configuration is still broken"
    return proc


def post_dataset(X):
    session = requests.Session()
    for i, row in enumerate(X):
        response = session.post(
            'http://127.0.0.1:8000/ingest',
            json={'features': [float(v) for v in row]},
            timeout=5,
        )
        assert response.status_code == 200, f"API rejected row {i}: HTTP {response.status_code} {response.text[:200]}"
        body = response.json()
        assert body.get('status') == 'ok', f"Unexpected API response for row {i}: {body}"


def wait_for_pipeline(X, proc, timeout):
    expected = canonical(X)
    deadline = time.time() + timeout
    last_error = 'no output was produced'
    while time.time() < deadline:
        assert proc.poll() is None, f"Worker exited with status {proc.returncode}"
        try:
            frame = pd.read_csv('/home/user/reduced_data.csv')
            assert list(frame.columns) == ['pc1', 'pc2']
            actual = frame.values
            if actual.shape != expected.shape:
                last_error = f"output shape is {actual.shape}, expected {expected.shape}"
                time.sleep(0.25)
                continue
            mae = aligned_mae(actual, expected)
            if not np.isfinite(mae) or mae >= 0.01:
                last_error = f"PCA MAE is {mae}"
                time.sleep(0.25)
                continue

            plot_path = '/home/user/cluster_plot.png'
            capture_path = '/tmp/verifier_scatter.npz'
            if not os.path.exists(plot_path) or os.path.getsize(plot_path) <= 15000:
                last_error = 'plot is absent or too small'
                time.sleep(0.25)
                continue
            with np.load(capture_path) as capture:
                sx = np.asarray(capture['x']).reshape(-1)
                sy = np.asarray(capture['y']).reshape(-1)
            if sx.shape != (len(actual),) or sy.shape != (len(actual),):
                last_error = f"scatter contains {len(sx)} points, expected {len(actual)}"
                time.sleep(0.25)
                continue
            if not (np.allclose(sx, actual[:, 0], atol=1e-8, rtol=1e-7) and
                    np.allclose(sy, actual[:, 1], atol=1e-8, rtol=1e-7)):
                last_error = 'scatter inputs do not match reduced_data.csv'
                time.sleep(0.25)
                continue

            image = mpimg.imread(plot_path)
            assert image.ndim in (2, 3) and image.size > 0, "Plot is not a decodable image"
            rgb = image if image.ndim == 2 else image[..., :3]
            background = np.median(rgb.reshape(-1, rgb.shape[-1]), axis=0) if rgb.ndim == 3 else np.median(rgb)
            distance = np.max(np.abs(rgb - background), axis=-1) if rgb.ndim == 3 else np.abs(rgb - background)
            assert np.mean(distance > 0.03) > 0.001, "Plot image is effectively blank"
            return
        except (FileNotFoundError, pd.errors.EmptyDataError, ValueError, EOFError, OSError, AssertionError) as exc:
            last_error = str(exc)
            time.sleep(0.25)
    pytest.fail(f"Pipeline did not produce the required result before timeout: {last_error}")


def test_live_multiservice_pipeline_and_worker_artifact():
    assert os.path.isfile('/app/worker.py'), "/app/worker.py is missing"

    r = redis.Redis(host='127.0.0.1', port=6379, socket_connect_timeout=2, socket_timeout=2)
    assert r.ping(), "Redis is not running on localhost:6379"

    import uvicorn  # noqa: F401 -- dependency explicitly required by the task
    response = requests.get('http://127.0.0.1:8000/openapi.json', timeout=5)
    assert response.status_code == 200, "The FastAPI ingestion service is not running on port 8000"
    assert '/ingest' in response.json().get('paths', {}), "Running API does not expose /ingest"

    assert worker_pids(), "No running /app/worker.py service was found"

    hook_dir = install_scatter_hook()

    # Exercise the real API -> Redis -> worker path with data unavailable as a file.
    rng = np.random.RandomState(20260317)
    challenge = rng.normal(size=(1200, 50))
    challenge[:, 5] += 0.7 * challenge[:, 0]
    challenge[:, 17] -= 0.4 * challenge[:, 2]
    worker = start_clean_worker(r, hook_dir)
    post_dataset(challenge)
    wait_for_pipeline(challenge, worker, timeout=90)

    # Reset worker state, then reproduce the requested final 10,000-row run through the API.
    raw = pd.read_csv('/home/user/raw_sensors.csv').values
    worker = start_clean_worker(r, hook_dir)
    post_dataset(raw)
    wait_for_pipeline(raw, worker, timeout=150)

    # Leave all three services running and retain the required final artifacts.
    assert worker.poll() is None
    assert r.ping()
    assert requests.get('http://127.0.0.1:8000/openapi.json', timeout=5).status_code == 200
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
