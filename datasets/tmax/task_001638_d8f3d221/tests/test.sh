#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import networkx as nx
import pytest
from scipy.stats import binom

CLASSIFIER_PATH = "/home/user/classifier.py"
NOTEBOOK_PATH = "/home/user/analysis.ipynb"
CLEAN_CORPUS_DIR = "/app/verifier_corpus/clean"
EVIL_CORPUS_DIR = "/app/verifier_corpus/evil"
CORPUS_DIR = "/app/corpus"
FINAL_RESULT_PATH = "/home/user/final_result.json"
MAX_VALENCY = {'H': 1, 'O': 2, 'N': 3, 'C': 4}


def run_classifier(path):
    return subprocess.run(
        ["python3", CLASSIFIER_PATH, str(path)],
        capture_output=True,
        timeout=10,
    ).returncode


def test_classifier_clean_corpus():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script is missing at {CLASSIFIER_PATH}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean corpus files found to test."

    failed_clean = []
    for cf in clean_files:
        if run_classifier(cf) != 0:
            failed_clean.append(os.path.basename(cf))

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {failed_clean}"


def test_classifier_evil_corpus():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script is missing at {CLASSIFIER_PATH}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found to test."

    failed_evil = []
    for ef in evil_files:
        if run_classifier(ef) != 1:
            failed_evil.append(os.path.basename(ef))

    assert not failed_evil, f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {failed_evil}"


def test_classifier_generated_adversarial_cases():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script is missing at {CLASSIFIER_PATH}"
    rng = random.Random(secrets.randbits(64))

    with tempfile.TemporaryDirectory(prefix="molecule_cases_") as td:
        td = Path(td)
        failures = []
        cases = []

        # Randomized valid graphs with nonconsecutive IDs, shuffled atom order,
        # disconnected atoms, and varied elements and filenames.
        for i in range(24):
            center_element = rng.choice(list(MAX_VALENCY))
            degree = rng.randint(0, MAX_VALENCY[center_element])
            ids = rng.sample(range(1000, 10000), degree + rng.randint(2, 5))
            center = ids[0]
            atoms = [{"id": center, "element": center_element}]
            bonds = []
            for leaf in ids[1:degree + 1]:
                atoms.append({"id": leaf, "element": "H"})
                bonds.append([center, leaf])
            for isolated in ids[degree + 1:]:
                atoms.append({"id": isolated, "element": rng.choice(list(MAX_VALENCY))})
            rng.shuffle(atoms)
            rng.shuffle(bonds)
            cases.append((0, {"atoms": atoms, "bonds": bonds}))

        # Every invalid graph exceeds the selected atom's stated valency by one,
        # while all leaf atoms remain within their own limits.
        for i in range(24):
            center_element = rng.choice(list(MAX_VALENCY))
            degree = MAX_VALENCY[center_element] + 1
            ids = rng.sample(range(10000, 50000), degree + 1)
            atoms = [{"id": ids[0], "element": center_element}]
            atoms += [{"id": x, "element": "H"} for x in ids[1:]]
            bonds = [[ids[0], x] for x in ids[1:]]
            rng.shuffle(atoms)
            rng.shuffle(bonds)
            cases.append((1, {"atoms": atoms, "bonds": bonds}))

        rng.shuffle(cases)
        for i, (expected, data) in enumerate(cases):
            subdir = td / secrets.token_hex(5)
            subdir.mkdir()
            path = subdir / (secrets.token_hex(8) + ".json")
            path.write_text(json.dumps(data))
            actual = run_classifier(path)
            if actual != expected:
                failures.append((i, expected, actual))

        assert not failures, f"Classifier failed generated cases: {failures[:10]}"


def is_clean(filepath):
    with open(filepath, 'r') as f:
        data = json.load(f)

    max_valency = {'H': 1, 'O': 2, 'N': 3, 'C': 4}
    degrees = {atom['id']: 0 for atom in data.get('atoms', [])}
    for bond in data.get('bonds', []):
        degrees[bond[0]] += 1
        degrees[bond[1]] += 1

    for atom in data.get('atoms', []):
        if degrees[atom['id']] > max_valency.get(atom['element'], 0):
            return False
    return True


def graph_metric(filepath):
    with open(filepath, 'r') as f:
        data = json.load(f)
    graph = nx.Graph()
    graph.add_nodes_from(atom['id'] for atom in data.get('atoms', []))
    graph.add_edges_from((bond[0], bond[1]) for bond in data.get('bonds', []))
    return nx.average_clustering(graph)


def write_graph(path, atoms, bonds):
    with open(path, "w") as f:
        json.dump({"atoms": atoms, "bonds": bonds}, f)


def prepare_hidden_corpus():
    # Remove leftovers in case a local harness invokes this verifier repeatedly.
    for old in Path(CORPUS_DIR).glob(".verifier_dynamic_*"):
        if old.is_dir():
            shutil.rmtree(old)
        else:
            old.unlink()

    # Choose a hidden even sample size for which the finite bootstrap percentile
    # is well separated from the 2.5% probability boundary.
    candidates = []
    for n in range(36, 61, 2):
        q = int(binom.ppf(0.025, n, 0.5))
        below = float(binom.cdf(q - 1, n, 0.5))
        at = float(binom.cdf(q, n, 0.5))
        if min(0.025 - below, at - 0.025) > 0.006:
            candidates.append(n)
    assert candidates
    n = secrets.choice(candidates)

    hidden = Path(CORPUS_DIR) / (".verifier_dynamic_" + secrets.token_hex(8))
    hidden.mkdir()

    # The original corpus contributes one clean zero-clustering graph. Add an
    # equal mixture of zero-clustering paths and unit-clustering triangles.
    for i in range(n // 2):
        base = 100000 + i * 10
        atoms = [
            {"id": base, "element": "C"},
            {"id": base + 1, "element": "C"},
            {"id": base + 2, "element": "C"},
        ]
        bonds = [[base, base + 1], [base + 1, base + 2], [base + 2, base]]
        write_graph(hidden / (secrets.token_hex(7) + ".json"), atoms, bonds)

    for i in range(n // 2 - 1):
        base = 200000 + i * 10
        atoms = [{"id": base, "element": "C"}, {"id": base + 1, "element": "C"}]
        write_graph(hidden / (secrets.token_hex(7) + ".json"), atoms, [[base, base + 1]])

    # Hidden invalid files ensure the notebook cannot simply count every JSON.
    for i in range(4):
        base = 300000 + i * 10
        atoms = [{"id": base, "element": "H"},
                 {"id": base + 1, "element": "C"},
                 {"id": base + 2, "element": "C"}]
        write_graph(hidden / (secrets.token_hex(7) + ".json"), atoms,
                    [[base, base + 1], [base, base + 2]])
    return n


def notebook_source():
    assert os.path.isfile(NOTEBOOK_PATH), f"Notebook is missing at {NOTEBOOK_PATH}"
    try:
        with open(NOTEBOOK_PATH, "r") as f:
            notebook = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        pytest.fail(f"analysis.ipynb is not a valid notebook JSON file: {exc}")
    assert isinstance(notebook, dict) and isinstance(notebook.get("cells"), list), "Invalid notebook structure"
    code_cells = [cell for cell in notebook["cells"] if cell.get("cell_type") == "code"]
    assert code_cells, "Notebook contains no executable code cells"
    parts = []
    for cell in code_cells:
        source = cell.get("source", "")
        parts.append("".join(source) if isinstance(source, list) else str(source))
    return "\n".join(parts)


def test_notebook_execution_and_final_result():
    requested_n = prepare_hidden_corpus()
    source = notebook_source()
    compact = source.lower().replace("_", "")
    assert "classifier.py" in source, "Notebook does not invoke the required classifier.py"

    # Permit either explicit extracted parameters or code which transcribes and
    # parses the supplied audio at execution time.
    explicit_resamples = bool(re.search(r"(?<!\d)5000(?!\d)", compact) or "five thousand" in compact)
    explicit_confidence = bool(re.search(r"(?<!\d)(?:0\.95|95)(?!\d)", compact) or "ninety-five" in compact or "ninety five" in compact)
    dynamic_audio = "pi_instructions.wav" in source and any(
        word in compact for word in ("whisper", "transcrib", "speech", "audio")
    )
    assert explicit_resamples or dynamic_audio, "Notebook does not use or extract the required 5000 resamples"
    assert explicit_confidence or dynamic_audio, "Notebook does not use or extract the required 95% confidence level"

    # Remove any precomputed answer. The notebook itself must recreate it from
    # the hidden corpus during an actual Jupyter execution.
    if os.path.exists(FINAL_RESULT_PATH):
        os.unlink(FINAL_RESULT_PATH)
    completed = subprocess.run(
        ["jupyter", "nbconvert", "--to", "notebook", "--execute", NOTEBOOK_PATH,
         "--output", "verified-analysis.ipynb", "--output-dir", "/tmp",
         "--ExecutePreprocessor.timeout=180"],
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, (
        "Notebook execution failed:\n" + completed.stdout[-2000:] + completed.stderr[-4000:]
    )
    assert os.path.isfile(FINAL_RESULT_PATH), f"Final result file is missing at {FINAL_RESULT_PATH}"

    with open(FINAL_RESULT_PATH, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Final result is not a valid JSON file.")

    metric = result.get("metric", "").lower().replace("_", " ")
    assert "average" in metric and "clustering" in metric and "coefficient" in metric, \
        f"Incorrect metric name: {result.get('metric')}"

    clean_paths = []
    for root, _, files in os.walk(CORPUS_DIR):
        for file in files:
            if file.endswith('.json'):
                path = os.path.join(root, file)
                if is_clean(path):
                    clean_paths.append(path)

    clean_count = len(clean_paths)
    assert clean_count == requested_n, f"Verifier corpus construction error: expected {requested_n}, got {clean_count}"
    assert result.get("num_clean_graphs") == clean_count, \
        f"Expected {clean_count} clean graphs, got {result.get('num_clean_graphs')}"

    # Recompute the requested graph metric independently for every clean graph.
    values = [graph_metric(path) for path in clean_paths]
    assert all(math.isclose(v, 0.0, abs_tol=1e-12) or math.isclose(v, 1.0, abs_tol=1e-12) for v in values)
    assert math.isclose(sum(values) / len(values), 0.5, abs_tol=1e-12)

    ci_lower = result.get("ci_lower")
    ci_upper = result.get("ci_upper")
    assert isinstance(ci_lower, (int, float)) and not isinstance(ci_lower, bool), "ci_lower must be a number"
    assert isinstance(ci_upper, (int, float)) and not isinstance(ci_upper, bool), "ci_upper must be a number"
    assert math.isfinite(ci_lower) and math.isfinite(ci_upper), "Confidence bounds must be finite"
    assert 0 <= ci_lower <= ci_upper <= 1, f"CIs must be valid probabilities, got [{ci_lower}, {ci_upper}]"

    # For this hidden empirical distribution, each bootstrap mean is Binomial(n,
    # 0.5)/n. These are the independently derived 95% percentile bounds. A small
    # tolerance accommodates Monte Carlo sampling and standard bootstrap variants.
    expected_lower = float(binom.ppf(0.025, clean_count, 0.5) / clean_count)
    expected_upper = float(binom.ppf(0.975, clean_count, 0.5) / clean_count)
    tolerance = 0.51 / clean_count + 0.002
    assert abs(float(ci_lower) - expected_lower) <= tolerance, (
        f"Incorrect lower bootstrap bound: expected about {expected_lower}, got {ci_lower}"
    )
    assert abs(float(ci_upper) - expected_upper) <= tolerance, (
        f"Incorrect upper bootstrap bound: expected about {expected_upper}, got {ci_upper}"
    )

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
