#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import bisect
import glob
import json
import math
import os
import runpy
import sys
import time

import numpy as np
import pytest
from sklearn.decomposition import PCA as RealPCA

REPORT_PATH = "/home/user/report.json"
CORPUS_PATH = "/home/user/data/corpus_embeddings.npy"
QUERY_PATH = "/home/user/data/query_embeddings.npy"
CANDIDATES = [16, 32, 64, 128]
EXECUTION = {}


def _find_submission_script():
    matches = []
    for path in glob.glob("/home/user/**/*.py", recursive=True):
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                source = f.read()
        except (OSError, UnicodeError):
            continue
        score = sum(token in source for token in (
            "corpus_embeddings.npy", "query_embeddings.npy", "report.json",
            "PCA", "n_components", "cosine"
        ))
        if "corpus_embeddings.npy" in source and "query_embeddings.npy" in source and "report.json" in source:
            matches.append((score, path, source))
    assert matches, "No Python evaluation script was found under /home/user"
    matches.sort(key=lambda item: (-item[0], len(item[1]), item[1]))
    return matches[0][1], matches[0][2]


def _uses_time_module(source):
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"Evaluation script is not valid Python: {exc}")

    module_aliases = set()
    function_aliases = set()
    clocks = {"time", "perf_counter", "process_time", "monotonic"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "time":
                    module_aliases.add(alias.asname or "time")
        elif isinstance(node, ast.ImportFrom) and node.module == "time":
            for alias in node.names:
                if alias.name in clocks:
                    function_aliases.add(alias.asname or alias.name)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id in module_aliases and node.func.attr in clocks:
                return True
        elif isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            return True
    return False


def _execute_submission():
    path, source = _find_submission_script()
    assert _uses_time_module(source), "Evaluation script does not benchmark retrieval using the time module"

    import sklearn.decomposition

    pca_events = []
    load_events = []
    clock_events = {name: [] for name in ("time", "perf_counter", "process_time", "monotonic")}
    original_load = np.load
    original_pca = sklearn.decomposition.PCA
    original_clocks = {name: getattr(time, name) for name in clock_events}

    class TrackingPCA(original_pca):
        def __init__(self, n_components=None, *, copy=True, whiten=False, svd_solver="auto", tol=0.0,
                     iterated_power="auto", n_oversamples=10, power_iteration_normalizer="auto",
                     random_state=None):
            super().__init__(n_components=n_components, copy=copy, whiten=whiten,
                             svd_solver=svd_solver, tol=tol, iterated_power=iterated_power,
                             n_oversamples=n_oversamples,
                             power_iteration_normalizer=power_iteration_normalizer,
                             random_state=random_state)
            self._verification_event = {
                "n_components": n_components,
                "random_state": random_state,
                "fit_shapes": [],
                "fit_transform_shapes": [],
                "transform_shapes": []
            }
            pca_events.append(self._verification_event)

        def fit(self, X, y=None):
            self._verification_event["fit_shapes"].append(list(np.shape(X)))
            return super().fit(X, y)

        def fit_transform(self, X, y=None):
            self._verification_event["fit_transform_shapes"].append(list(np.shape(X)))
            return super().fit_transform(X, y)

        def transform(self, X):
            self._verification_event["transform_shapes"].append(list(np.shape(X)))
            return super().transform(X)

    def tracked_load(file, *args, **kwargs):
        try:
            load_events.append(os.path.realpath(os.fspath(file)))
        except TypeError:
            pass
        return original_load(file, *args, **kwargs)

    def make_clock(name):
        original = original_clocks[name]
        def tracked_clock():
            value = original()
            clock_events[name].append(value)
            return value
        return tracked_clock

    if os.path.lexists(REPORT_PATH):
        assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a regular file"
        os.remove(REPORT_PATH)

    old_argv = sys.argv[:]
    old_cwd = os.getcwd()
    np.load = tracked_load
    sklearn.decomposition.PCA = TrackingPCA
    for name in clock_events:
        setattr(time, name, make_clock(name))

    try:
        sys.argv = [path]
        os.chdir(os.path.dirname(path) or "/home/user")
        runpy.run_path(path, run_name="__main__")
    finally:
        sys.argv = old_argv
        os.chdir(old_cwd)
        np.load = original_load
        sklearn.decomposition.PCA = original_pca
        for name, original in original_clocks.items():
            setattr(time, name, original)

    EXECUTION.update({
        "path": path,
        "pca_events": pca_events,
        "load_events": load_events,
        "clock_events": clock_events
    })


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_artifact():
    _execute_submission()

    assert os.path.realpath(CORPUS_PATH) in EXECUTION["load_events"], "Script did not load corpus_embeddings.npy"
    assert os.path.realpath(QUERY_PATH) in EXECUTION["load_events"], "Script did not load query_embeddings.npy"

    for n_components in CANDIDATES:
        matching = [event for event in EXECUTION["pca_events"]
                    if event["n_components"] == n_components and event["random_state"] == 42]
        assert matching, f"PCA(n_components={n_components}, random_state=42) was not initialized"
        exercised = False
        for event in matching:
            fitted = [5000, 384] in event["fit_shapes"] or [5000, 384] in event["fit_transform_shapes"]
            query_transformed = [100, 384] in event["transform_shapes"]
            if fitted and query_transformed:
                exercised = True
                break
        assert exercised, f"PCA candidate {n_components} was not fit on the corpus and applied to the queries"

    assert sum(len(values) for values in EXECUTION["clock_events"].values()) >= 4, \
        "The script did not perform both required timed benchmarks"


def _load_report():
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")


def _expected_results():
    corpus = np.load(CORPUS_PATH)
    queries = np.load(QUERY_PATH)

    corpus_norm = corpus / np.linalg.norm(corpus, axis=1, keepdims=True)
    query_norm = queries / np.linalg.norm(queries, axis=1, keepdims=True)
    baseline_sim = query_norm @ corpus_norm.T
    baseline_top = np.argsort(-baseline_sim, axis=1)[:, :10]

    recalls = {}
    for n_components in CANDIDATES:
        pca = RealPCA(n_components=n_components, random_state=42)
        reduced_corpus = pca.fit_transform(corpus)
        reduced_queries = pca.transform(queries)
        reduced_corpus /= np.linalg.norm(reduced_corpus, axis=1, keepdims=True)
        reduced_queries /= np.linalg.norm(reduced_queries, axis=1, keepdims=True)
        reduced_sim = reduced_queries @ reduced_corpus.T
        reduced_top = np.argsort(-reduced_sim, axis=1)[:, :10]
        recalls[n_components] = float(np.mean([
            len(set(baseline_top[i]).intersection(reduced_top[i])) / 10.0
            for i in range(len(queries))
        ]))

    eligible = [n for n in CANDIDATES if recalls[n] >= 0.85]
    assert eligible, "Test data unexpectedly has no PCA candidate meeting Recall@10 >= 0.85"
    optimal = min(eligible)
    return optimal, round(recalls[optimal], 4)


def _matches_measured_interval(value):
    tolerance = max(0.005, abs(value) * 0.05)
    for values in EXECUTION["clock_events"].values():
        for start in values:
            target = start + value
            pos = bisect.bisect_left(values, target)
            for index in (pos - 1, pos):
                if 0 <= index < len(values) and values[index] >= start:
                    if abs((values[index] - start) - value) <= tolerance:
                        return True
    return False


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file."


def test_report_structure_and_types():
    report = _load_report()
    required_keys = {
        "baseline_shape", "optimal_n_components", "optimal_recall_at_10",
        "latency_raw_seconds", "latency_optimal_seconds"
    }
    missing_keys = required_keys - set(report.keys())
    assert not missing_keys, f"Missing required keys in report.json: {missing_keys}"

    assert report["baseline_shape"] == [5000, 384], \
        f"Expected baseline_shape to be [5000, 384], got {report['baseline_shape']}"

    assert isinstance(report["optimal_n_components"], int) and not isinstance(report["optimal_n_components"], bool), \
        f"optimal_n_components must be an integer, got {type(report['optimal_n_components'])}"
    assert report["optimal_n_components"] in CANDIDATES, \
        f"optimal_n_components {report['optimal_n_components']} is not in the candidate list {CANDIDATES}"
    assert report["optimal_n_components"] == 64, \
        f"Expected optimal_n_components to be 64 based on the synthetic data threshold, got {report['optimal_n_components']}"

    assert isinstance(report["optimal_recall_at_10"], (float, int)) and not isinstance(report["optimal_recall_at_10"], bool), \
        f"optimal_recall_at_10 must be a float, got {type(report['optimal_recall_at_10'])}"
    assert math.isfinite(report["optimal_recall_at_10"])
    assert 0.85 <= report["optimal_recall_at_10"] <= 1.0, \
        f"optimal_recall_at_10 should be >= 0.85 and <= 1.0, got {report['optimal_recall_at_10']}"
    recall_str = str(report["optimal_recall_at_10"])
    if "." in recall_str:
        decimals = len(recall_str.split(".")[1])
        assert decimals <= 4, \
            f"optimal_recall_at_10 should be rounded to 4 decimal places, got {report['optimal_recall_at_10']}"

    for key in ("latency_raw_seconds", "latency_optimal_seconds"):
        assert isinstance(report[key], (float, int)) and not isinstance(report[key], bool), \
            f"{key} must be a float, got {type(report[key])}"
        assert math.isfinite(report[key]) and report[key] > 0, f"{key} must be finite and > 0, got {report[key]}"
        assert _matches_measured_interval(float(report[key])), \
            f"{key} does not match an elapsed interval measured while executing the evaluation script"


def test_report_matches_recomputed_pca_retrieval():
    report = _load_report()
    expected_optimal, expected_recall = _expected_results()
    assert report["optimal_n_components"] == expected_optimal, \
        f"Expected recomputed optimal dimension {expected_optimal}, got {report['optimal_n_components']}"
    assert math.isclose(float(report["optimal_recall_at_10"]), expected_recall, rel_tol=0, abs_tol=5e-5), \
        f"Expected recomputed Recall@10 {expected_recall}, got {report['optimal_recall_at_10']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
