#!/bin/bash
set -e
mkdir -p /logs/verifier

STUB_DIR="/tmp/verifier_stubs"
rm -rf "$STUB_DIR"
mkdir -p "$STUB_DIR/sentence_transformers"

cat <<'PY_EOF' > "$STUB_DIR/sentence_transformers/__init__.py"
import hashlib
import json
import os
import numpy as np
from . import util


def _vector(text):
    raw = hashlib.sha256(str(text).encode("utf-8")).digest()[:16]
    return np.asarray([(b - 127.5) / 127.5 for b in raw], dtype=np.float32)


def _record(event):
    path = os.environ.get("ST_EVENT_LOG")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")


class SentenceTransformer:
    def __init__(self, model_name, *args, **kwargs):
        self.model_name = str(model_name)
        _record({"event": "model", "name": self.model_name})

    def encode(self, sentences, *args, **kwargs):
        single = isinstance(sentences, str)
        if single:
            values = [sentences]
        else:
            try:
                values = list(sentences)
            except TypeError:
                values = [sentences]
                single = True
        values = [str(v) for v in values]
        _record({"event": "encode", "texts": values})
        result = np.vstack([_vector(v) for v in values])
        if kwargs.get("normalize_embeddings"):
            norms = np.linalg.norm(result, axis=1, keepdims=True)
            result = result / np.where(norms == 0, 1, norms)
        if single:
            result = result[0]
        if kwargs.get("convert_to_tensor"):
            import torch
            return torch.tensor(result)
        return result

    def similarity(self, a, b):
        return util.cos_sim(a, b)
PY_EOF

cat <<'PY_EOF' > "$STUB_DIR/sentence_transformers/util.py"
import torch


def _tensor(value):
    if isinstance(value, torch.Tensor):
        result = value.float()
    else:
        result = torch.as_tensor(value, dtype=torch.float32)
    if result.ndim == 1:
        result = result.unsqueeze(0)
    return result


def cos_sim(a, b):
    a = _tensor(a)
    b = _tensor(b)
    a = a / torch.clamp(torch.linalg.vector_norm(a, dim=1, keepdim=True), min=1e-12)
    b = b / torch.clamp(torch.linalg.vector_norm(b, dim=1, keepdim=True), min=1e-12)
    return a @ b.T


def semantic_search(query_embeddings, corpus_embeddings, top_k=10, **kwargs):
    scores = cos_sim(query_embeddings, corpus_embeddings)
    results = []
    for row in scores:
        order = torch.argsort(row, descending=True)[:top_k]
        results.append([{"corpus_id": int(i), "score": float(row[i])} for i in order])
    return results
PY_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd

HOME = Path("/home/user")
CSV_PATH = HOME / "tickets.csv"
OUTPUT_PATH = HOME / "best_match.txt"
QUERY = "I forgot my login details and the reset email is not arriving."
STUB_DIR = "/tmp/verifier_stubs"


def test_best_match_file_exists():
    """Keep the original existence assertion."""
    assert OUTPUT_PATH.is_file(), f"The file {OUTPUT_PATH} is missing."


def test_best_match_content():
    """Keep the original expected-result assertion."""
    assert OUTPUT_PATH.is_file(), f"The file {OUTPUT_PATH} is missing."
    content = OUTPUT_PATH.read_text(encoding="utf-8").strip()
    assert content == "105", f"Expected '105' in {OUTPUT_PATH}, but got '{content}'."


def _vector(text):
    raw = hashlib.sha256(str(text).encode("utf-8")).digest()[:16]
    return np.asarray([(b - 127.5) / 127.5 for b in raw], dtype=float)


def _expected_id(rows):
    cleaned = [r for r in rows if r[1] is not None and r[1] != "" and 15 <= len(r[1]) <= 200]
    query = _vector(QUERY)
    scores = []
    for ticket_id, text in cleaned:
        vector = _vector(text)
        score = float(np.dot(query, vector) / (np.linalg.norm(query) * np.linalg.norm(vector)))
        scores.append((score, ticket_id))
    return max(scores, key=lambda item: item[0])[1], [text for _, text in cleaned]


def _make_case():
    token = secrets.token_hex(12)
    ids = list(range(secrets.randbelow(500000) + 10000, secrets.randbelow(500000) + 10000 + 20))
    # Make IDs unique even if the two random offsets above happened to interact oddly.
    base = secrets.randbelow(800000) + 10000
    ids = [base + i * 17 for i in range(10)]
    valid = [
        f"Account access investigation {token}",
        f"Reset delivery troubleshooting {token[::-1]}",
        f"Customer support request number {token[:10]}",
        ("boundary" + token)[:15].ljust(15, "x"),
        ("maximum-length " + token).ljust(200, "z")[:200],
        " " * 15,
    ]
    short = ("s" + token)[:14]
    long_text = ("overlong " + token).ljust(201, "q")
    rows = [
        (ids[0], valid[0]),
        (ids[1], None),
        (ids[2], short),
        (ids[3], valid[1]),
        (ids[4], ""),
        (ids[5], long_text),
        (ids[6], valid[2]),
        (ids[7], valid[3]),
        (ids[8], valid[4]),
        (ids[9], valid[5]),
    ]
    # Vary row order so a fixed row selection cannot pass.
    rng = np.random.default_rng(secrets.randbits(64))
    rng.shuffle(rows)
    return rows, {short, long_text}


def _candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in {"venv", "node_modules", "__pycache__"}]
        for name in files:
            if name.endswith(".py"):
                path = Path(root) / name
                if path.is_file() and path.stat().st_size <= 1_000_000:
                    candidates.append(path)
    return sorted(candidates)


def _events_are_valid(log_path, cleaned_texts, invalid_texts):
    try:
        events = [json.loads(line) for line in Path(log_path).read_text(encoding="utf-8").splitlines() if line]
    except Exception:
        return False
    models = [e.get("name", "") for e in events if e.get("event") == "model"]
    if not any(name.rsplit("/", 1)[-1] == "all-MiniLM-L6-v2" for name in models):
        return False
    encoded = []
    for event in events:
        if event.get("event") == "encode":
            encoded.extend(event.get("texts", []))
    if QUERY not in encoded:
        return False
    if not all(text in encoded for text in cleaned_texts):
        return False
    if any(text in encoded for text in invalid_texts):
        return False
    return True


def _run_candidate(script, cases):
    env = os.environ.copy()
    env["PYTHONPATH"] = STUB_DIR + os.pathsep + env.get("PYTHONPATH", "")
    for index, (rows, invalid_texts) in enumerate(cases):
        expected, cleaned_texts = _expected_id(rows)
        pd.DataFrame(rows, columns=["ticket_id", "text"]).to_csv(CSV_PATH, index=False)
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        event_log = f"/tmp/st_events_{os.getpid()}_{index}.jsonl"
        Path(event_log).unlink(missing_ok=True)
        env["ST_EVENT_LOG"] = event_log
        try:
            result = subprocess.run(
                ["python3", str(script)],
                cwd=str(HOME),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=120,
                check=False,
            )
        except Exception:
            return False
        if result.returncode != 0 or not OUTPUT_PATH.is_file():
            return False
        if OUTPUT_PATH.read_text(encoding="utf-8").strip() != str(expected):
            return False
        if not _events_are_valid(event_log, cleaned_texts, invalid_texts):
            return False
    return True


def test_pipeline_script_exists_and_executes_correctly():
    scripts = _candidate_scripts()
    assert scripts, "No Python script was written under /home/user."
    original_csv = CSV_PATH.read_bytes() if CSV_PATH.exists() else None
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    try:
        cases = [_make_case(), _make_case()]
        assert any(_run_candidate(script, cases) for script in scripts), (
            "No submitted Python script successfully cleaned the data, loaded "
            "all-MiniLM-L6-v2, embedded the cleaned texts and query, and produced "
            "the cosine-similarity result on verifier-generated inputs."
        )
    finally:
        if original_csv is None:
            CSV_PATH.unlink(missing_ok=True)
        else:
            CSV_PATH.write_bytes(original_csv)
        if original_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(original_output)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
