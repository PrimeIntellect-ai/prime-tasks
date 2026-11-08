#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import tempfile

import pandas as pd
import pytest
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

RUN_SH = "/home/user/run.sh"
TRAIN_PY = "/home/user/train.py"
DATA_PATH = "/home/user/data.csv"
RESULTS_PATH = "/home/user/results.json"


def load_results():
    assert os.path.exists(RESULTS_PATH), f"File not found: {RESULTS_PATH}. Did train.py run successfully?"
    try:
        with open(RESULTS_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")


def test_run_sh_exists_and_executable():
    """Verify that /home/user/run.sh exists and is executable."""
    assert os.path.exists(RUN_SH), f"File not found: {RUN_SH}"
    assert os.path.isfile(RUN_SH), f"Path is not a file: {RUN_SH}"
    st = os.stat(RUN_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {RUN_SH} is not executable"


def test_train_py_exists():
    """Verify that /home/user/train.py exists."""
    assert os.path.exists(TRAIN_PY), f"File not found: {TRAIN_PY}"
    assert os.path.isfile(TRAIN_PY), f"Path is not a file: {TRAIN_PY}"


def test_run_sh_execution():
    """Verify that /home/user/run.sh executes successfully."""
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    try:
        subprocess.run([RUN_SH], check=True, capture_output=True, text=True, timeout=120)
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"{RUN_SH} failed to execute with return code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )


def test_results_json():
    """Verify that /home/user/results.json is created and has the correct format."""
    results = load_results()
    assert "best_alpha" in results, f"Key 'best_alpha' missing in {RESULTS_PATH}"
    assert "best_score" in results, f"Key 'best_score' missing in {RESULTS_PATH}"
    assert isinstance(results["best_alpha"], (int, float)), "best_alpha must be a number"
    assert isinstance(results["best_score"], (int, float)), "best_score must be a number"
    assert results["best_alpha"] in [0.1, 1.0, 10.0], (
        f"best_alpha {results['best_alpha']} is not one of the grid values [0.1, 1.0, 10.0]"
    )


def test_train_rejects_incorrect_thread_environment():
    saved = open(RESULTS_PATH, "rb").read() if os.path.exists(RESULTS_PATH) else None
    try:
        cases = [
            (None, "1"),
            ("1", None),
            ("2", "1"),
            ("1", "2"),
        ]
        for openblas, omp in cases:
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
            env = os.environ.copy()
            if openblas is None:
                env.pop("OPENBLAS_NUM_THREADS", None)
            else:
                env["OPENBLAS_NUM_THREADS"] = openblas
            if omp is None:
                env.pop("OMP_NUM_THREADS", None)
            else:
                env["OMP_NUM_THREADS"] = omp
            proc = subprocess.run(
                ["python3", TRAIN_PY],
                env=env,
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=60,
            )
            assert proc.returncode != 0, (
                "train.py must fail unless OPENBLAS_NUM_THREADS and OMP_NUM_THREADS are both exactly '1'"
            )
            assert not os.path.exists(RESULTS_PATH), "train.py produced results despite an invalid environment"
    finally:
        if saved is not None:
            with open(RESULTS_PATH, "wb") as f:
                f.write(saved)
        elif os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)


def test_required_sklearn_configuration_is_used():
    audit_dir = tempfile.mkdtemp(prefix="train_audit_")
    audit_path = os.path.join(audit_dir, "events.jsonl")
    sitecustomize = r'''
import json
import os
import sklearn.feature_extraction.text as _text
import sklearn.linear_model as _linear
import sklearn.model_selection as _selection

_path = os.environ.get("TRAIN_AUDIT_PATH")
def _emit(event):
    if _path:
        with open(_path, "a") as f:
            f.write(json.dumps(event) + "\\n")

_real_vectorizer = _text.CountVectorizer
_real_ridge = _linear.Ridge
_real_grid = _selection.GridSearchCV

def CountVectorizer(*args, **kwargs):
    obj = _real_vectorizer(*args, **kwargs)
    _emit({"kind": "vectorizer", "max_features": obj.max_features, "stop_words": obj.stop_words})
    return obj

def Ridge(*args, **kwargs):
    obj = _real_ridge(*args, **kwargs)
    _emit({"kind": "ridge", "random_state": obj.random_state})
    return obj

def GridSearchCV(*args, **kwargs):
    obj = _real_grid(*args, **kwargs)
    _emit({
        "kind": "grid",
        "param_grid": obj.param_grid,
        "cv": obj.cv,
        "scoring": obj.scoring,
        "estimator_random_state": getattr(obj.estimator, "random_state", None),
    })
    return obj

_text.CountVectorizer = CountVectorizer
_linear.Ridge = Ridge
_selection.GridSearchCV = GridSearchCV
'''
    with open(os.path.join(audit_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["OPENBLAS_NUM_THREADS"] = "1"
    env["OMP_NUM_THREADS"] = "1"
    env["TRAIN_AUDIT_PATH"] = audit_path
    env["PYTHONPATH"] = audit_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    proc = subprocess.run(
        ["python3", TRAIN_PY], env=env, cwd="/home/user", capture_output=True, text=True, timeout=120
    )
    assert proc.returncode == 0, f"train.py failed under valid environment. Stdout: {proc.stdout}\nStderr: {proc.stderr}"
    assert os.path.exists(audit_path), "train.py did not instantiate the required sklearn components"
    with open(audit_path) as f:
        events = [json.loads(line) for line in f if line.strip()]

    vectors = [e for e in events if e.get("kind") == "vectorizer"]
    ridges = [e for e in events if e.get("kind") == "ridge"]
    grids = [e for e in events if e.get("kind") == "grid"]
    assert any(e.get("max_features") == 50 and e.get("stop_words") == "english" for e in vectors), (
        "CountVectorizer must use max_features=50 and stop_words='english'"
    )
    assert any(e.get("random_state") == 42 for e in ridges), "Ridge must use random_state=42"
    assert any(
        e.get("param_grid") == {"alpha": [0.1, 1.0, 10.0]}
        and e.get("cv") == 3
        and e.get("scoring") is None
        and e.get("estimator_random_state") == 42
        for e in grids
    ), "GridSearchCV must use the required alpha grid, cv=3, Ridge estimator, and default scoring"


def _word(i):
    return "token" + chr(ord("a") + i // 26) + chr(ord("a") + i % 26)


def test_pipeline_recomputes_correct_result_on_unseen_data():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    original_results = open(RESULTS_PATH, "rb").read() if os.path.exists(RESULTS_PATH) else None
    try:
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        vocab = [_word(i) for i in range(80)]
        rows = []
        for i in range(75):
            tokens = [rng.choice(vocab) for _ in range(rng.randint(8, 18))]
            tokens += [rng.choice(["the", "and", "is", "of"]) for _ in range(rng.randint(1, 6))]
            target = (
                1.4 * tokens.count(vocab[3])
                - 1.1 * tokens.count(vocab[7])
                + 0.8 * tokens.count(vocab[12])
                - 0.6 * tokens.count(vocab[25])
                + rng.gauss(0, 0.15)
            )
            rows.append({"text": " ".join(tokens), "target": target})
        challenge = pd.DataFrame(rows)
        challenge.to_csv(DATA_PATH, index=False)

        X = CountVectorizer(max_features=50, stop_words="english").fit_transform(challenge["text"])
        expected_search = GridSearchCV(
            Ridge(random_state=42), {"alpha": [0.1, 1.0, 10.0]}, cv=3
        )
        expected_search.fit(X, challenge["target"])
        expected_alpha = float(expected_search.best_params_["alpha"])
        expected_score = float(round(expected_search.best_score_, 4))

        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        env = os.environ.copy()
        env["OPENBLAS_NUM_THREADS"] = "7"
        env["OMP_NUM_THREADS"] = "9"
        proc = subprocess.run(
            [RUN_SH], env=env, cwd="/home/user", capture_output=True, text=True, timeout=120
        )
        assert proc.returncode == 0, (
            f"run.sh failed when required to override inherited thread settings. "
            f"Stdout: {proc.stdout}\nStderr: {proc.stderr}"
        )
        results = load_results()
        assert set(results.keys()) == {"best_alpha", "best_score"}, (
            "results.json must contain exactly best_alpha and best_score"
        )
        assert isinstance(results["best_alpha"], (int, float)), "best_alpha must be numeric"
        assert isinstance(results["best_score"], (int, float)), "best_score must be numeric"
        assert float(results["best_alpha"]) == expected_alpha, (
            f"Incorrect best_alpha: expected {expected_alpha}, got {results['best_alpha']}"
        )
        assert float(results["best_score"]) == expected_score, (
            f"Incorrect best_score: expected {expected_score}, got {results['best_score']}"
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if original_results is not None:
            with open(RESULTS_PATH, "wb") as f:
                f.write(original_results)
        elif os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
