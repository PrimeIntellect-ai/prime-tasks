#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "joblib:joblib"; do
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

# The submitted application may already be running as requested. Stop it so the
# verifier can independently exercise benchmark.sh and then launch app.py itself.
if command -v fuser >/dev/null 2>&1; then
    fuser -k 5000/tcp >/dev/null 2>&1 || true
else
    pkill -f '^python3 .*\/home\/user\/app.py' >/dev/null 2>&1 || true
fi
sleep 0.5

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline


def make_golden_model():
    df = pd.read_csv('/home/user/cleaned_data.csv')
    pipeline = Pipeline([
        ('tfidf', TfidfVectorizer(stop_words='english')),
        ('clf', LogisticRegression(random_state=42, solver='liblinear')),
    ])
    search = GridSearchCV(
        pipeline,
        {'clf__C': [0.1, 1.0, 10.0]},
        cv=3,
        scoring='accuracy',
    )
    search.fit(df['text'], df['label'])
    return df, search


def test_phase1_cleaned_data():
    """Verify that cleaned_data.csv exactly matches the required deduplication."""
    cleaned_path = '/home/user/cleaned_data.csv'
    assert os.path.exists(cleaned_path), f'{cleaned_path} does not exist.'

    df = pd.read_csv('/home/user/raw_data.csv')
    vec = TfidfVectorizer(stop_words='english')
    matrix = vec.fit_transform(df['text'])
    kept_indices = []
    for i in range(len(df)):
        if not kept_indices:
            kept_indices.append(i)
        elif cosine_similarity(matrix[i], matrix[kept_indices]).max() < 0.80:
            kept_indices.append(i)

    golden_path = '/tmp/golden_cleaned.csv'
    df.iloc[kept_indices].reset_index(drop=True).to_csv(golden_path, index=False)
    with open(cleaned_path, 'r', encoding='utf-8') as f:
        user_data = f.read().strip()
    with open(golden_path, 'r', encoding='utf-8') as f:
        golden_data = f.read().strip()
    assert user_data == golden_data, (
        'The contents of cleaned_data.csv do not match the expected '
        'TF-IDF cosine-similarity deduplication.'
    )


def test_phase2_model_and_param():
    """Recompute GridSearchCV and validate the saved fitted pipeline."""
    param_path = '/home/user/best_param.txt'
    model_path = '/home/user/model.joblib'
    assert os.path.exists(param_path), f'{param_path} does not exist.'
    assert os.path.exists(model_path), f'{model_path} does not exist.'

    with open(param_path, 'r', encoding='utf-8') as f:
        param_text = f.read().strip()
    assert param_text in ['0.1', '1.0', '10.0'], (
        f"best_param.txt contains an unexpected value: '{param_text}'."
    )

    df, search = make_golden_model()
    expected_c = float(search.best_params_['clf__C'])
    assert float(param_text) == expected_c, (
        f'best_param.txt contains {param_text}, but the required GridSearchCV '
        f'selects {expected_c}.'
    )

    try:
        model = joblib.load(model_path)
    except Exception as exc:
        pytest.fail(f'model.joblib could not be loaded: {exc}')

    assert isinstance(model, Pipeline), 'model.joblib is not a scikit-learn Pipeline.'
    assert len(model.steps) == 2, 'The saved pipeline must contain exactly the vectorizer and classifier.'
    vectorizers = [step for _, step in model.steps if isinstance(step, TfidfVectorizer)]
    classifiers = [step for _, step in model.steps if isinstance(step, LogisticRegression)]
    assert len(vectorizers) == 1 and len(classifiers) == 1, (
        'The pipeline must contain one TfidfVectorizer and one LogisticRegression.'
    )
    vectorizer = vectorizers[0]
    classifier = classifiers[0]
    assert vectorizer.stop_words == 'english'
    assert classifier.random_state == 42
    assert classifier.solver == 'liblinear'
    assert float(classifier.C) == expected_c
    assert hasattr(vectorizer, 'vocabulary_'), 'The vectorizer is not fitted.'
    assert hasattr(classifier, 'coef_'), 'The classifier is not fitted.'

    golden = search.best_estimator_
    golden_vec = golden.named_steps['tfidf']
    golden_clf = golden.named_steps['clf']
    assert vectorizer.vocabulary_ == golden_vec.vocabulary_
    np.testing.assert_allclose(vectorizer.idf_, golden_vec.idf_, rtol=1e-10, atol=1e-12)
    np.testing.assert_array_equal(classifier.classes_, golden_clf.classes_)
    np.testing.assert_allclose(classifier.coef_, golden_clf.coef_, rtol=1e-8, atol=1e-10)
    np.testing.assert_allclose(classifier.intercept_, golden_clf.intercept_, rtol=1e-8, atol=1e-10)

    probes = list(df['text']) + [
        'Is this a valid test message?',
        'A delicious cheese pizza for dinner.',
        'Statistics and algorithms power machine learning.',
        'A fox and a dog are animals.',
    ]
    np.testing.assert_array_equal(model.predict(probes), golden.predict(probes))


class CountingServer(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, address, delay):
        super().__init__(address, CountingHandler)
        self.delay = delay
        self.count = 0
        self.valid_count = 0
        self.active = 0
        self.max_active = 0
        self.lock = threading.Lock()


class CountingHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        valid = False
        try:
            valid = (
                self.path == '/predict'
                and self.headers.get_content_type() == 'application/json'
                and json.loads(body.decode('utf-8'))
                    == {'text': 'Is this a valid test message?'}
            )
        except Exception:
            valid = False

        with self.server.lock:
            self.server.count += 1
            self.server.valid_count += int(valid)
            self.server.active += 1
            self.server.max_active = max(self.server.max_active, self.server.active)
        try:
            time.sleep(self.server.delay)
            payload = json.dumps({'prediction': 'test'}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            with self.server.lock:
                self.server.active -= 1

    def log_message(self, fmt, *args):
        pass


def run_benchmark(delay):
    server = CountingServer(('127.0.0.1', 5000), delay)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    start = time.monotonic()
    try:
        result = subprocess.run(
            ['bash', '/home/user/benchmark.sh'],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=30,
        )
        elapsed = time.monotonic() - start
        assert result.returncode == 0, (
            f'benchmark.sh failed. stdout={result.stdout!r}, stderr={result.stderr!r}'
        )
        time.sleep(0.2)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert server.count == 50, f'benchmark.sh sent {server.count} requests instead of 50.'
    assert server.valid_count == 50, 'Not all benchmark requests used the required endpoint and JSON payload.'
    assert server.max_active == 1, 'The 50 benchmark requests were not sent sequentially.'

    result_path = '/home/user/benchmark_results.txt'
    assert os.path.exists(result_path), f'{result_path} does not exist.'
    with open(result_path, 'r', encoding='utf-8') as f:
        text = f.read().strip()
    try:
        reported = float(text)
    except ValueError:
        pytest.fail(f"benchmark_results.txt does not contain a valid numeric time. Found: '{text}'")
    assert np.isfinite(reported) and reported > 0, 'Benchmark time must be a finite number greater than 0.'
    tolerance = max(0.75, elapsed * 0.25)
    assert abs(reported - elapsed) <= tolerance, (
        f'benchmark_results.txt reports {reported} seconds, but execution took '
        f'{elapsed:.3f} seconds.'
    )
    return reported


def request_prediction(text, timeout=5):
    req = urllib.request.Request(
        'http://127.0.0.1:5000/predict',
        data=json.dumps({'text': text}).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f'API returned status code {response.status}'
        try:
            return json.loads(response.read().decode('utf-8'))
        except json.JSONDecodeError:
            pytest.fail('API did not return valid JSON.')


def test_phase3_api_and_benchmark():
    """Execute the benchmark and application and verify their real behavior."""
    app_path = '/home/user/app.py'
    bench_path = '/home/user/benchmark.sh'
    result_path = '/home/user/benchmark_results.txt'
    assert os.path.exists(app_path), f'{app_path} does not exist.'
    assert os.path.exists(bench_path), f'{bench_path} does not exist.'
    assert os.path.exists(result_path), f'{result_path} does not exist.'

    fast = run_benchmark(0.005)
    slow = run_benchmark(0.050)
    assert slow > fast + 0.75, (
        'benchmark_results.txt did not track the deliberately changed total request time.'
    )

    _, search = make_golden_model()
    probes = [
        'Is this a valid test message?',
        'Pepperoni pizza with extra cheese.',
        'Neural networks and large datasets.',
        'The lazy dog and the quick fox.',
    ]
    expected = [str(value) for value in search.best_estimator_.predict(probes)]

    env = os.environ.copy()
    env['FLASK_DEBUG'] = '0'
    proc = subprocess.Popen(
        ['python3', app_path],
        cwd='/home/user',
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 12
        while True:
            if proc.poll() is not None:
                pytest.fail(f'app.py exited before serving requests (exit code {proc.returncode}).')
            try:
                request_prediction(probes[0], timeout=0.5)
                break
            except (urllib.error.URLError, TimeoutError):
                if time.monotonic() >= deadline:
                    pytest.fail('Failed to connect to the submitted app.py on port 5000.')
                time.sleep(0.2)

        for text, wanted in zip(probes, expected):
            data = request_prediction(text)
            assert 'prediction' in data, 'API response JSON does not contain the prediction key.'
            assert data['prediction'] == wanted, (
                f'API returned {data["prediction"]!r} for {text!r}; expected {wanted!r}.'
            )
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
