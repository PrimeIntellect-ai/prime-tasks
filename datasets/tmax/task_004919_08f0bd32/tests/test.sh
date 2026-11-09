#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

APP = "/home/user/app"
CLASSIFIER = os.path.join(APP, "classifier.py")
NOTEBOOK = os.path.join(APP, "orchestrate.ipynb")


def parse_fasta(file_path):
    seq_ids = []
    with open(file_path, "r") as f:
        for line in f:
            if line.startswith(">"):
                seq_ids.append(line[1:].strip())
    return seq_ids


def run_classifier(corpus_path, cwd):
    output = os.path.join(cwd, "classifications.json")
    if os.path.exists(output):
        os.unlink(output)
    subprocess.run(
        ["python3", CLASSIFIER, corpus_path],
        check=True,
        cwd=cwd,
        timeout=30,
    )
    assert os.path.exists(output), "classifications.json was not generated in the current working directory."
    with open(output, "r") as f:
        result = json.load(f)
    assert isinstance(result, dict), "classifications.json must contain a JSON object."
    return result


def test_services_running():
    """Verify that Nginx, Redis, Flask, and Celery are running."""
    try:
        assert subprocess.check_output(["redis-cli", "ping"], timeout=5).decode().strip() == "PONG"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        pytest.fail("Redis is not running or not responding to ping.")

    try:
        output = subprocess.check_output(["ps", "aux"], timeout=5).decode()
        assert "nginx" in output, "Nginx process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check processes for Nginx.")

    assert "api.py" in output or "flask" in output or "gunicorn" in output, "Flask API process is not running."
    assert "celery" in output, "Celery worker process is not running."


def test_end_to_end_simulation():
    """Verify that Nginx routes to Flask and the Celery worker completes the task."""
    payload = json.dumps({"sequence": "ATGC"}).encode("utf-8")
    req = urllib.request.Request(
        "http://localhost:8080/simulate",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        response = urllib.request.urlopen(req, timeout=10)
        assert response.status in [200, 202], f"Expected HTTP 200/202, got {response.status}"
        data = json.loads(response.read().decode())
        assert data is not None
        assert isinstance(data, dict) and data.get("task_id"), "API did not return a Celery task ID."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or enqueue task: {e}")

    sys.path.insert(0, APP)
    try:
        from worker import app as celery_app
        result = celery_app.AsyncResult(data["task_id"]).get(timeout=30, propagate=True)
    except Exception as e:
        pytest.fail(f"Celery worker did not successfully process the enqueued simulation: {e}")
    finally:
        if sys.path and sys.path[0] == APP:
            sys.path.pop(0)

    assert isinstance(result, list) and len(result) == 2, "Celery returned an invalid simulation result."
    assert all(isinstance(row, list) and row for row in result), "Simulation result arrays are missing."


def test_classifier_clean_corpus():
    """Verify classifier accepts 100% of clean sequences."""
    corpus_path = "/home/user/data/clean_sequences.fasta"
    assert os.path.exists(CLASSIFIER), f"Classifier script not found at {CLASSIFIER}"
    try:
        classifications = run_classifier(corpus_path, APP)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Classifier script failed on clean corpus: {e}")

    rejected = [seq_id for seq_id in parse_fasta(corpus_path)
                if classifications.get(seq_id) != "accept"]
    if rejected:
        pytest.fail(f"{len(rejected)} clean sequences rejected. Offending IDs: {rejected[:5]}")


def test_classifier_evil_corpus():
    """Verify classifier rejects 100% of evil sequences."""
    corpus_path = "/home/user/data/evil_sequences.fasta"
    try:
        classifications = run_classifier(corpus_path, APP)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Classifier script failed on evil corpus: {e}")

    bypassed = [seq_id for seq_id in parse_fasta(corpus_path)
                if classifications.get(seq_id) != "reject"]
    if bypassed:
        pytest.fail(f"{len(bypassed)} evil sequences bypassed. Offending IDs: {bypassed[:5]}")


def test_classifier_on_unseen_sequences_and_ids():
    """Exercise sequence-based behavior on a hidden path with opaque randomized IDs."""
    rng = random.Random(981734)
    records = []

    # Safe sequences, including the exact 80% GC boundary (worker uses > 0.8).
    safe = [
        "ACGTGATCCGTTAGCA",
        "GCGCGCGCGCGCGCGAATTA",  # 16/20 GC = 0.8
        "ATATATATACGCGTTA",       # near-repeat but not the worker's motif
    ]
    # Unsafe for the exact conditions implemented by worker.pcr_kinetics.
    unsafe = [
        "G" * 19 + "A",          # 95% GC
        "CCGCGGCGCCGCGGCGCCGA",  # >80% GC
        "TGCATATATATATGGCTA",    # contains ATATATATAT
    ]

    alphabet = "ACGT"
    while len(safe) < 9:
        seq = "".join(rng.choice(alphabet) for _ in range(rng.randint(17, 31)))
        gc = (seq.count("G") + seq.count("C")) / len(seq)
        if gc <= 0.8 and "ATATATATAT" not in seq:
            safe.append(seq)
    while len(unsafe) < 9:
        length = rng.randint(17, 31)
        seq = "".join(rng.choice("GGC") for _ in range(length - 2)) + "AT"
        if (seq.count("G") + seq.count("C")) / len(seq) > 0.8:
            unsafe.append(seq)

    for seq in safe + unsafe:
        opaque_id = "s_" + uuid.uuid4().hex
        gc = (seq.count("G") + seq.count("C")) / len(seq) if seq else 0
        expected = "reject" if gc > 0.8 or "ATATATATAT" in seq else "accept"
        records.append((opaque_id, seq, expected))
    rng.shuffle(records)

    with tempfile.TemporaryDirectory(prefix="sequence-check-") as td:
        corpus = os.path.join(td, "input_" + uuid.uuid4().hex + ".fasta")
        with open(corpus, "w") as f:
            for seq_id, seq, _ in records:
                f.write(f">{seq_id}\n{seq}\n")
        classifications = run_classifier(corpus, td)

        expected_ids = {seq_id for seq_id, _, _ in records}
        assert set(classifications) == expected_ids, "Output IDs must exactly match the input FASTA IDs."
        wrong = [(seq_id, expected, classifications.get(seq_id))
                 for seq_id, _, expected in records
                 if classifications.get(seq_id) != expected]
        assert not wrong, f"Classifier failed unseen sequence-based cases: {wrong[:5]}"
        assert set(classifications.values()) <= {"accept", "reject"}


def test_orchestrate_notebook_exists():
    """Verify the Jupyter notebook orchestrate.ipynb exists."""
    assert os.path.isfile(NOTEBOOK), f"{NOTEBOOK} is missing."


def test_orchestrate_notebook_executes_and_posts_only_accepted_sequences():
    """Execute the notebook through papermill on hidden data and observe its POST payloads."""
    import nbformat

    with open(NOTEBOOK, "r") as f:
        nb = nbformat.read(f, as_version=4)
    code = "\n".join(cell.source for cell in nb.cells if cell.cell_type == "code")
    assert re.search(r"(^|\n)\s*(?:import\s+classifier\b|from\s+classifier\s+import\b)", code), \
        "Notebook must import classifier."

    accepted_seq = "ACGTTGCACTGACCATGCTA"
    rejected_seq = "ACGATATATATATGGTCA"

    with tempfile.TemporaryDirectory(prefix="notebook-check-") as td:
        corpus = os.path.join(td, "target_" + uuid.uuid4().hex + ".fasta")
        with open(corpus, "w") as f:
            f.write(f">{uuid.uuid4().hex}\n{accepted_seq}\n")
            f.write(f">{uuid.uuid4().hex}\n{rejected_seq}\n")

        request_log = os.path.join(td, "requests.jsonl")
        import_log = os.path.join(td, "imports.log")
        input_nb = os.path.join(td, "instrumented.ipynb")
        output_nb = os.path.join(td, "executed.ipynb")

        # Replace a notebook's target FASTA literal while preserving its workflow.
        replacements = 0
        fasta_literal = re.compile(r"(['\"])([^'\"\n]*\.(?:fasta|fa))\1", re.IGNORECASE)
        for cell in nb.cells:
            if cell.cell_type != "code":
                continue
            cell.source, count = fasta_literal.subn(lambda m: repr(corpus), cell.source)
            replacements += count
        assert replacements > 0, "Notebook must define a target FASTA path that papermill can execute."

        instrumentation = nbformat.v4.new_code_cell(f'''
import builtins as _audit_builtins
import json as _audit_json
import urllib.request as _audit_urllib
import requests as _audit_requests
_AUDIT_REQUEST_LOG = {request_log!r}
_AUDIT_IMPORT_LOG = {import_log!r}
_audit_original_import = _audit_builtins.__import__
def _audit_import(name, globals=None, locals=None, fromlist=(), level=0):
    if name == "classifier" or name.endswith(".classifier"):
        with open(_AUDIT_IMPORT_LOG, "a") as _f:
            _f.write(name + "\\n")
    return _audit_original_import(name, globals, locals, fromlist, level)
_audit_builtins.__import__ = _audit_import
class _AuditResponse:
    status_code = 202
    status = 202
    reason = "Accepted"
    text = '{{"task_id":"notebook-audit"}}'
    content = text.encode()
    headers = {{"Content-Type": "application/json"}}
    def json(self): return {{"task_id": "notebook-audit"}}
    def read(self, *args, **kwargs): return self.content
    def raise_for_status(self): return None
    def getcode(self): return 202
    def __enter__(self): return self
    def __exit__(self, *args): return False
def _audit_record(url, payload):
    try:
        if isinstance(payload, (bytes, bytearray)): payload = payload.decode()
        if isinstance(payload, str): payload = _audit_json.loads(payload)
    except Exception:
        pass
    with open(_AUDIT_REQUEST_LOG, "a") as _f:
        _f.write(_audit_json.dumps({{"url": str(url), "payload": payload}}, default=str) + "\\n")
def _audit_post(url, *args, **kwargs):
    payload = kwargs.get("json", kwargs.get("data", args[0] if args else None))
    _audit_record(url, payload)
    return _AuditResponse()
def _audit_request(method, url, *args, **kwargs):
    if str(method).upper() == "POST":
        payload = kwargs.get("json", kwargs.get("data", args[0] if args else None))
        _audit_record(url, payload)
    return _AuditResponse()
def _audit_urlopen(req, *args, **kwargs):
    url = getattr(req, "full_url", req)
    method = getattr(req, "method", None) or ("POST" if getattr(req, "data", None) is not None else "GET")
    if str(method).upper() == "POST": _audit_record(url, getattr(req, "data", kwargs.get("data")))
    return _AuditResponse()
_audit_requests.post = _audit_post
_audit_requests.request = _audit_request
_audit_requests.sessions.Session.request = lambda self, method, url, *a, **kw: _audit_request(method, url, *a, **kw)
_audit_urllib.urlopen = _audit_urlopen
''')
        nb.cells.insert(0, instrumentation)
        nbformat.write(nb, input_nb)

        proc = subprocess.run(
            ["papermill", input_nb, output_nb, "-k", "python3"],
            cwd=APP,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
        assert proc.returncode == 0, f"Notebook is not papermill-executable:\n{proc.stdout[-4000:]}"
        assert os.path.isfile(output_nb), "Papermill did not produce an executed notebook."
        assert os.path.exists(import_log) and open(import_log).read().strip(), \
            "Notebook did not execute its classifier import."
        assert os.path.exists(request_log), "Notebook sent no POST requests for accepted sequences."

        records = [json.loads(line) for line in open(request_log) if line.strip()]
        posts = [r for r in records if r.get("url") == "http://localhost:8080/simulate"]
        assert posts, "Notebook did not POST to http://localhost:8080/simulate."
        payload_sequences = [r.get("payload", {}).get("sequence")
                             for r in posts if isinstance(r.get("payload"), dict)]
        assert accepted_seq in payload_sequences, "Notebook did not send the actual accepted FASTA sequence."
        assert rejected_seq not in payload_sequences, "Notebook sent a rejected sequence to the simulation API."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
