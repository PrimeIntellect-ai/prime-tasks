#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "sklearn:scikit-learn"; do
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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import subprocess

import cv2
import joblib
import numpy as np
import pytest
from sklearn.base import ClassifierMixin
from sklearn.feature_extraction.text import CountVectorizer, HashingVectorizer, TfidfVectorizer
from sklearn.pipeline import Pipeline


def test_plot_results():
    path = '/home/user/cv_results.png'
    assert os.path.isfile(path), f"File {path} is missing. Did you fix and run plot_results.py?"
    assert os.path.getsize(path) > 0, f"File {path} is empty."

    script_path = '/app/plot_results.py'
    assert os.path.isfile(script_path), f"Plotting script {script_path} is missing."

    with open(script_path, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Plotting script is not valid Python: {e}")

    show_lines = []
    save_lines = []
    explicit_agg = False
    constants = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            constants.append(node.value.lower())
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == 'show':
                show_lines.append(node.lineno)
            elif node.func.attr == 'savefig':
                save_lines.append(node.lineno)
            elif node.func.attr in ('use', 'switch_backend'):
                if any(isinstance(arg, ast.Constant) and str(arg.value).lower() == 'agg' for arg in node.args):
                    explicit_agg = True

    # Accept the hinted Agg fix, removing show(), or saving before show().
    env_agg = 'agg' in constants and 'mplbackend' in constants
    safe_order = bool(save_lines) and (not show_lines or min(save_lines) < min(show_lines))
    assert explicit_agg or env_agg or safe_order, (
        "plot_results.py still calls show() before savefig() without explicitly selecting the Agg backend"
    )

    os.unlink(path)
    try:
        result = subprocess.run(
            ['python3', script_path], cwd='/app', capture_output=True,
            text=True, timeout=30
        )
    except subprocess.TimeoutExpired:
        pytest.fail('plot_results.py timed out when executed')
    assert result.returncode == 0, (
        f"plot_results.py failed when executed:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(path), f"Running {script_path} did not create {path}."
    assert os.path.getsize(path) > 0, f"Running {script_path} created an empty file."

    image = cv2.imread(path, cv2.IMREAD_COLOR)
    assert image is not None, f"{path} is not a readable image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "The generated plot is unexpectedly small."
    assert float(np.std(image)) > 2.0 and len(np.unique(image.reshape(-1, 3), axis=0)) > 10, (
        "The generated plot appears blank or contains no plotted content."
    )


def _load_and_validate_model():
    model_path = '/home/user/best_model.pkl'
    assert os.path.isfile(model_path), f"Model file {model_path} is missing."

    try:
        model = joblib.load(model_path)
    except Exception as e:
        pytest.fail(f"Failed to load model from {model_path}: {e}")

    assert isinstance(model, Pipeline), (
        "best_model.pkl must contain a fitted sklearn Pipeline, not a hand-written predictor"
    )
    vectorizer_types = (CountVectorizer, TfidfVectorizer, HashingVectorizer)
    assert any(isinstance(step, vectorizer_types) for _, step in model.steps), (
        "The saved pipeline does not include a text vectorizer"
    )
    classifier = model.steps[-1][1]
    assert isinstance(classifier, ClassifierMixin) or getattr(classifier, '_estimator_type', None) == 'classifier', (
        "The final pipeline step is not a classifier"
    )
    assert classifier.__class__.__module__.startswith('sklearn.'), (
        "The final classifier must be a fitted sklearn classifier"
    )
    return model


def test_model_accuracy():
    model = _load_and_validate_model()

    positive_words = ["good", "great", "excellent", "amazing", "wonderful", "fantastic", "superb"]
    negative_words = ["bad", "terrible", "awful", "horrible", "poor", "disgusting", "useless"]

    random.seed(99)
    test_texts = []
    test_labels = []
    for _ in range(200):
        if random.random() > 0.5:
            text = f"I think it is {random.choice(positive_words)}."
            test_labels.append(1)
        else:
            text = f"I think it is {random.choice(negative_words)}."
            test_labels.append(0)

    try:
        preds = model.predict(test_texts)
    except Exception as e:
        pytest.fail(f"Model prediction failed: {e}")

    acc = sum(p == l for p, l in zip(preds, test_labels)) / len(test_labels)
    assert acc >= 0.85, f"Model accuracy {acc} is below the threshold of 0.85."


def test_model_against_video_derived_labels():
    model = _load_and_validate_model()

    with open('/app/texts.csv', 'r', encoding='utf-8') as f:
        texts = [line.rstrip('\r\n') for line in f]

    cap = cv2.VideoCapture('/app/labels.mp4')
    assert cap.isOpened(), 'Could not open /app/labels.mp4'
    labels = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        mean_bgr = frame.mean(axis=(0, 1))
        labels.append(1 if mean_bgr[1] > mean_bgr[2] else 0)
    cap.release()

    assert len(texts) == 1000, f"Expected 1000 texts, found {len(texts)}"
    assert len(labels) == len(texts), (
        f"Video yielded {len(labels)} labels for {len(texts)} texts"
    )

    try:
        preds = model.predict(texts)
    except Exception as e:
        pytest.fail(f"Pipeline failed on the supplied dataset: {e}")
    dataset_acc = float(np.mean(np.asarray(preds) == np.asarray(labels)))
    assert dataset_acc >= 0.85, (
        f"Model accuracy on labels decoded from the video is {dataset_acc}, below 0.85"
    )

    # Derive discriminative tokens and expected answers from the actual CSV/video,
    # then exercise the pipeline in fresh sentence contexts.
    token_labels = {}
    token_support = {}
    for text, label in zip(texts, labels):
        for token in set(re.findall(r"[A-Za-z]+", text.lower())):
            token_labels.setdefault(token, set()).add(label)
            token_support[token] = token_support.get(token, 0) + 1

    by_label = {
        label: sorted(token for token, seen in token_labels.items()
                      if seen == {label} and token_support[token] >= 10)
        for label in (0, 1)
    }
    assert by_label[0] and by_label[1], 'Could not derive discriminative tokens from the dataset'

    rng = random.SystemRandom()
    challenge_texts = []
    challenge_labels = []
    templates = [
        'My verdict: {}.',
        'In summary, {}!',
        'The experience can only be called {}.',
        'Review keyword -- {} -- end.'
    ]
    for i in range(200):
        label = i % 2
        token = rng.choice(by_label[label])
        challenge_texts.append(rng.choice(templates).format(token))
        challenge_labels.append(label)

    try:
        challenge_preds = model.predict(challenge_texts)
    except Exception as e:
        pytest.fail(f"Pipeline failed on derived test inputs: {e}")
    challenge_acc = float(np.mean(np.asarray(challenge_preds) == np.asarray(challenge_labels)))
    assert challenge_acc >= 0.85, (
        f"Model accuracy on dynamically derived text inputs is {challenge_acc}, below 0.85"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
