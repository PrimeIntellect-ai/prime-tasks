#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pickle
import re
import subprocess
import tempfile
import uuid

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.utils.validation import check_is_fitted

FEATURES = ["brightness", "contrast", "sharpness", "motion_corr"]


def run_detector(csv_path, env=None):
    result = subprocess.run(
        ["python3", "/home/user/detector.py", csv_path],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def load_model():
    with open("/home/user/model.pkl", "rb") as f:
        return pickle.load(f)


def test_required_files_exist():
    expected_files = [
        "/home/user/train.py",
        "/home/user/model.pkl",
        "/home/user/detector.py",
        "/home/user/video_features.csv",
        "/home/user/video_result.txt",
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."


def test_training_script_executes_and_creates_fitted_pipeline_with_ci():
    with open("/home/user/train.py", "r") as f:
        source = f.read()

    tree = ast.parse(source)
    assert any(isinstance(n, ast.Name) and n.id == "Pipeline" for n in ast.walk(tree)), \
        "train.py must construct a scikit-learn Pipeline."
    assert not any(
        isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute)
        and n.func.attr == "fit_transform"
        for n in ast.walk(tree)
    ), "PCA must not be fit_transform'ed before train_test_split."

    result = subprocess.run(
        ["python3", "/home/user/train.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    assert os.path.isfile("/home/user/model.pkl")

    model = load_model()
    assert isinstance(model, Pipeline), "model.pkl must contain a sklearn Pipeline."

    pca_positions = [i for i, (_, step) in enumerate(model.steps) if isinstance(step, PCA)]
    lr_positions = [i for i, (_, step) in enumerate(model.steps) if isinstance(step, LogisticRegression)]
    assert pca_positions, "The saved pipeline must contain PCA."
    assert lr_positions, "The saved pipeline must contain LogisticRegression."
    assert pca_positions[0] < lr_positions[-1], "PCA must precede LogisticRegression."
    assert lr_positions[-1] == len(model.steps) - 1, "LogisticRegression must be the final estimator."

    pca = model.steps[pca_positions[0]][1]
    clf = model.steps[lr_positions[-1]][1]
    check_is_fitted(pca)
    check_is_fitted(clf)

    df = pd.read_csv("/home/user/train_data.csv")
    n_total = len(df)
    n_train = int(pca.n_samples_)
    assert 0 < n_train < n_total, \
        "PCA must be fitted by the pipeline on only the training split, not the full dataset."
    n_test = n_total - n_train

    ci_lines = [line for line in result.stdout.splitlines()
                if "95" in line and ("confidence" in line.lower() or "ci" in line.lower())]
    assert ci_lines, f"train.py did not print a 95% confidence interval. Output: {result.stdout!r}"
    values = [float(x) for x in re.findall(r"(?<![A-Za-z])[+-]?(?:\d+\.\d+|\.\d+|\d+)(?:[eE][+-]?\d+)?", ci_lines[-1])]
    assert len(values) >= 3, f"Could not parse two confidence bounds from: {ci_lines[-1]!r}"
    low, high = values[-2], values[-1]
    assert low <= high
    center = (low + high) / 2.0
    expected_margin = 1.96 * np.sqrt(max(center * (1.0 - center), 0.0) / n_test)
    actual_margin = (high - low) / 2.0
    assert -0.02 <= low <= 1.02 and -0.02 <= high <= 1.02
    assert abs(actual_margin - expected_margin) <= 0.015, \
        "The printed interval is not the normal-approximation 95% accuracy interval."


def test_detector_source_uses_predict_proba():
    with open("/home/user/detector.py", "r") as f:
        tree = ast.parse(f.read())
    assert any(isinstance(n, ast.Attribute) and n.attr == "predict_proba" for n in ast.walk(tree)), \
        "detector.py must use model.predict_proba."


def test_detector_follows_model_probabilities_on_unlabelled_random_paths():
    model = load_model()
    rng = np.random.default_rng(20260911)

    frames = [
        pd.DataFrame(rng.normal([0.5, 0.5, 0.5, 0.5], 0.08, size=(37, 4)), columns=FEATURES),
        pd.DataFrame(rng.normal([0.8, 0.2, 0.3, 0.9], 0.08, size=(43, 4)), columns=FEATURES),
        pd.DataFrame(rng.uniform(0.1, 0.9, size=(29, 4)), columns=FEATURES),
    ]

    with tempfile.TemporaryDirectory(prefix="detector_probe_") as td:
        for frame in frames:
            path = os.path.join(td, uuid.uuid4().hex + ".csv")
            frame.to_csv(path, index=False)
            mean_probability = float(model.predict_proba(frame[FEATURES])[:, 1].mean())
            expected = "EVIL" if mean_probability > 0.5 else "CLEAN"
            assert run_detector(path) == expected


def test_detector_calls_probabilities_not_predict_or_path_rules():
    model_path = "/home/user/model.pkl"
    with open(model_path, "rb") as f:
        original_model = f.read()

    module_path = "/tmp/verifier_probability_model.py"
    with open(module_path, "w") as f:
        f.write('''import numpy as np\nclass ProbabilityOnlyModel:\n    classes_ = np.array([0, 1])\n    def predict(self, X):\n        raise RuntimeError("predict must not be used")\n    def decision_function(self, X):\n        raise RuntimeError("decision_function must not be used")\n    def predict_proba(self, X):\n        values = np.asarray(X, dtype=float)\n        p = np.where(values[:, 0] > 0, 0.9, 0.1)\n        return np.column_stack([1.0 - p, p])\n''')

    try:
        import sys
        sys.path.insert(0, "/tmp")
        from verifier_probability_model import ProbabilityOnlyModel
        with open(model_path, "wb") as f:
            pickle.dump(ProbabilityOnlyModel(), f)

        env = os.environ.copy()
        env["PYTHONPATH"] = "/tmp" + os.pathsep + env.get("PYTHONPATH", "")
        with tempfile.TemporaryDirectory(prefix="opaque_inputs_") as td:
            positive = pd.DataFrame(np.full((11, 4), 2.0), columns=FEATURES)
            negative = pd.DataFrame(np.full((11, 4), -2.0), columns=FEATURES)
            positive_path = os.path.join(td, uuid.uuid4().hex + ".csv")
            negative_path = os.path.join(td, uuid.uuid4().hex + ".csv")
            positive.to_csv(positive_path, index=False)
            negative.to_csv(negative_path, index=False)
            assert run_detector(positive_path, env=env) == "EVIL"
            assert run_detector(negative_path, env=env) == "CLEAN"
    finally:
        with open(model_path, "wb") as f:
            f.write(original_model)


def test_video_features_were_extracted_and_result_matches():
    actual = pd.read_csv("/home/user/video_features.csv")
    assert list(actual.columns) == FEATURES
    assert len(actual) > 0

    with tempfile.TemporaryDirectory() as td:
        expected_path = os.path.join(td, "features.csv")
        result = subprocess.run(
            ["python3", "/home/user/extract.py", "/app/test_video.mp4", expected_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr
        expected = pd.read_csv(expected_path)
    pd.testing.assert_frame_equal(actual, expected)

    detector_result = run_detector("/home/user/video_features.csv")
    with open("/home/user/video_result.txt", "r") as f:
        saved_result = f.read().strip()
    assert saved_result == detector_result


def test_video_result():
    with open("/home/user/video_result.txt", "r") as f:
        content = f.read().strip()
    assert content == "EVIL", f"Expected /home/user/video_result.txt to contain 'EVIL', but got '{content}'."


def test_adversarial_corpus():
    evil_dir = "/app/eval_corpus/evil"
    clean_dir = "/app/eval_corpus/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]

    assert len(evil_files) > 0, "No CSV files found in evil corpus."
    assert len(clean_files) > 0, "No CSV files found in clean corpus."

    bypassed_evil = []
    for evil_csv in evil_files:
        output = run_detector(evil_csv)
        if output != "EVIL":
            bypassed_evil.append(os.path.basename(evil_csv))

    modified_clean = []
    for clean_csv in clean_files:
        output = run_detector(clean_csv)
        if output != "CLEAN":
            modified_clean.append(os.path.basename(clean_csv))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
