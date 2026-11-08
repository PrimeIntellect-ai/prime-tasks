#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import functools
import inspect
import itertools
import json
import os

from sklearn.feature_extraction.text import TfidfVectorizer

_log_path = os.environ.get("TFIDF_TRACK_LOG")
_counter = itertools.count(1)
_original_init = TfidfVectorizer.__init__
_original_fit = TfidfVectorizer.fit
_original_fit_transform = TfidfVectorizer.fit_transform
_original_transform = TfidfVectorizer.transform
_signature = inspect.signature(_original_init)


def _write(event):
    if _log_path:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")


def _documents(value):
    if isinstance(value, str):
        return [value]
    return list(value)


@functools.wraps(_original_init)
def _tracked_init(self, *args, **kwargs):
    bound = _signature.bind_partial(self, *args, **kwargs)
    defaults_only = True
    for name, value in bound.arguments.items():
        if name == "self":
            continue
        default = _signature.parameters[name].default
        try:
            equal = value == default
            if hasattr(equal, "all"):
                equal = bool(equal.all())
            else:
                equal = bool(equal)
        except Exception:
            equal = False
        if default is inspect.Parameter.empty or not equal:
            defaults_only = False
    _original_init(self, *args, **kwargs)
    self._verifier_vectorizer_id = next(_counter)
    _write({"event": "init", "id": self._verifier_vectorizer_id,
            "defaults_only": defaults_only})


def _id(obj):
    return getattr(obj, "_verifier_vectorizer_id", None)


@functools.wraps(_original_fit)
def _tracked_fit(self, raw_documents, y=None):
    docs = _documents(raw_documents)
    _write({"event": "fit", "id": _id(self), "documents": docs})
    return _original_fit(self, docs, y)


@functools.wraps(_original_fit_transform)
def _tracked_fit_transform(self, raw_documents, y=None):
    docs = _documents(raw_documents)
    _write({"event": "fit_transform", "id": _id(self), "documents": docs})
    return _original_fit_transform(self, docs, y)


@functools.wraps(_original_transform)
def _tracked_transform(self, raw_documents):
    docs = _documents(raw_documents)
    _write({"event": "transform", "id": _id(self), "documents": docs})
    return _original_transform(self, docs)


TfidfVectorizer.__init__ = _tracked_init
TfidfVectorizer.fit = _tracked_fit
TfidfVectorizer.fit_transform = _tracked_fit_transform
TfidfVectorizer.transform = _tracked_transform
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import string
import subprocess

import pandas as pd
import pytest
from scipy import stats
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

EVALUATE = "/home/user/evaluate.py"
DATA = "/home/user/data.csv"
RESULTS = "/home/user/results.json"
QUERY = "automated machine learning pipelines"
KEYS = [
    "control_mean_similarity",
    "treatment_mean_similarity",
    "t_statistic",
    "p_value",
]


def read_results():
    assert os.path.isfile(RESULTS), (
        f"Missing file: {RESULTS}. Did you save the results to the correct path?"
    )
    try:
        with open(RESULTS, "r", encoding="utf-8") as f:
            result = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS} is not a valid JSON file.")
    for key in KEYS:
        assert key in result, f"Missing key '{key}' in {RESULTS}."
        assert isinstance(result[key], (int, float)) and not isinstance(result[key], bool), (
            f"Value for '{key}' must be a number."
        )
    return result


def execute_and_read(tmp_path):
    if os.path.lexists(RESULTS):
        os.unlink(RESULTS)
    log = tmp_path / ("tfidf-" + secrets.token_hex(8) + ".jsonl")
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hook" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["TFIDF_TRACK_LOG"] = str(log)
    completed = subprocess.run(
        ["python3", EVALUATE], cwd="/home/user", env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert completed.returncode == 0, (
        "evaluate.py did not execute successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    results = read_results()
    events = []
    if log.exists():
        for line in log.read_text(encoding="utf-8").splitlines():
            events.append(json.loads(line))
    return results, events


def assert_independent_vectorizers(events, control_texts, treatment_texts):
    fit_events = [e for e in events if e.get("event") in ("fit", "fit_transform")]

    control_fits = [e for e in fit_events if e.get("documents") == control_texts]
    treatment_fits = [e for e in fit_events if e.get("documents") == treatment_texts]
    assert control_fits, "No TfidfVectorizer was fitted on exactly the Control texts."
    assert treatment_fits, "No TfidfVectorizer was fitted on exactly the Treatment texts."

    control_id = control_fits[0].get("id")
    treatment_id = treatment_fits[0].get("id")
    assert control_id is not None and treatment_id is not None
    assert control_id != treatment_id, (
        "Control and Treatment must use completely independent TfidfVectorizer instances."
    )

    init_by_id = {e.get("id"): e for e in events if e.get("event") == "init"}
    assert init_by_id.get(control_id, {}).get("defaults_only") is True, (
        "The Control TfidfVectorizer must use default parameters."
    )
    assert init_by_id.get(treatment_id, {}).get("defaults_only") is True, (
        "The Treatment TfidfVectorizer must use default parameters."
    )

    query_ids = {
        e.get("id") for e in events
        if e.get("event") == "transform" and e.get("documents") == [QUERY]
    }
    assert control_id in query_ids, (
        "The Control vectorizer must transform the exact target query."
    )
    assert treatment_id in query_ids, (
        "The Treatment vectorizer must transform the exact target query."
    )


def expected_for(frame):
    groups = {}
    for group in ("Control", "Treatment"):
        texts = frame.loc[frame["group"] == group, "text"].tolist()
        vectorizer = TfidfVectorizer()
        matrix = vectorizer.fit_transform(texts)
        query_vector = vectorizer.transform([QUERY])
        groups[group] = cosine_similarity(matrix, query_vector).flatten()
    t_stat, p_value = stats.ttest_ind(
        groups["Control"], groups["Treatment"], equal_var=False
    )
    return {
        "control_mean_similarity": round(float(groups["Control"].mean()), 4),
        "treatment_mean_similarity": round(float(groups["Treatment"].mean()), 4),
        "t_statistic": round(float(t_stat), 4),
        "p_value": round(float(p_value), 4),
    }


def randomized_frame():
    rng = secrets.SystemRandom()
    alphabet = string.ascii_lowercase

    def word(prefix):
        return prefix + "".join(rng.choice(alphabet) for _ in range(12))

    query_words = QUERY.split()
    rows = []
    next_id = 1
    for group, count in (("Control", 8), ("Treatment", 9)):
        shared = word("shared")
        fixed_masks = [15, 3, 12, 0]
        masks = fixed_masks + [rng.randrange(1, 16) for _ in range(count - 4)]
        for index, mask in enumerate(masks):
            terms = [term for bit, term in enumerate(query_words) if mask & (1 << bit)]
            terms.extend([shared] * rng.randrange(1, 4))
            terms.extend(word("noise") for _ in range(rng.randrange(1, 5)))
            if index % 3 == 0:
                terms.append(word("extra"))
            rows.append({"id": next_id, "group": group, "text": " ".join(terms)})
            next_id += 1
    return pd.DataFrame(rows)


def assert_values(actual, expected, tolerance):
    for key, expected_value in expected.items():
        assert abs(actual[key] - expected_value) <= tolerance, (
            f"Value for '{key}' is incorrect. Expected approximately "
            f"{expected_value}, but got {actual[key]}. Check your TF-IDF fitting "
            "and similarity calculations to ensure the data leak is fixed properly."
        )


def test_executed_pipeline_and_results(tmp_path):
    assert os.path.isfile(EVALUATE), f"Missing executable Python artifact: {EVALUATE}"
    original_data = open(DATA, "rb").read()
    original_frame = pd.read_csv(DATA)

    try:
        actual, events = execute_and_read(tmp_path)
        expected_values = {
            "control_mean_similarity": 0.1873,
            "treatment_mean_similarity": 0.4496,
            "t_statistic": -3.3768,
            "p_value": 0.0125,
        }
        assert_values(actual, expected_values, 1e-3)
        assert_independent_vectorizers(
            events,
            original_frame.loc[original_frame["group"] == "Control", "text"].tolist(),
            original_frame.loc[original_frame["group"] == "Treatment", "text"].tolist(),
        )

        for _ in range(2):
            probe = randomized_frame()
            probe.to_csv(DATA, index=False)
            expected = expected_for(probe)
            actual, events = execute_and_read(tmp_path)
            assert_values(actual, expected, 1e-4)
            assert_independent_vectorizers(
                events,
                probe.loc[probe["group"] == "Control", "text"].tolist(),
                probe.loc[probe["group"] == "Treatment", "text"].tolist(),
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)

    # Leave results.json corresponding to the real dataset, and verify it once more.
    final, _ = execute_and_read(tmp_path)
    assert_values(final, {
        "control_mean_similarity": 0.1873,
        "treatment_mean_similarity": 0.4496,
        "t_statistic": -3.3768,
        "p_value": 0.0125,
    }, 1e-3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
