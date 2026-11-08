#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import pytest

RESULT_PATH = Path('/home/user/results/top_matches.json')
METADATA_DIR = Path('/home/user/dataset_metadata')
QUERY = 'Medical chest X-ray images for pneumonia detection and classification'


def test_results_file_exists():
    """Check if the top_matches.json file exists in the correct directory."""
    file_path = "/home/user/results/top_matches.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."


def test_results_content():
    """Check if the top_matches.json contains the correct query and top 3 files."""
    file_path = "/home/user/results/top_matches.json"
    assert os.path.isfile(file_path), f"Cannot check content, {file_path} is missing."

    with open(file_path, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not a valid JSON.")

    expected_query = "Medical chest X-ray images for pneumonia detection and classification"
    expected_files = ["dataset_01.txt", "dataset_08.txt", "dataset_03.txt"]

    assert "query" in result, "JSON missing 'query' key."
    assert "top_3_files" in result, "JSON missing 'top_3_files' key."

    assert result["query"] == expected_query, f"Expected query '{expected_query}', but got '{result['query']}'."
    assert result["top_3_files"] == expected_files, f"Expected top_3_files to be {expected_files}, but got {result['top_3_files']}."


def _candidate_scripts():
    roots = [Path('/home/user'), Path('/root'), Path('/tmp'), Path('/opt'), Path('/workspace')]
    excluded = {Path('/tmp/test_final_state.py').resolve()}
    found = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob('*.py'):
            try:
                resolved = path.resolve()
                if resolved in excluded or '/site-packages/' in str(resolved):
                    continue
                source = path.read_text(errors='ignore')
            except (OSError, UnicodeError):
                continue
            if 'all-MiniLM-L6-v2' in source and 'sentence_transformers' in source:
                found.append(resolved)
    return sorted(set(found), key=str)


def _write_fake_sentence_transformers(fake_root, marker, descriptions, scores):
    package = Path(fake_root) / 'sentence_transformers'
    package.mkdir(parents=True)
    vectors = {
        QUERY: [1.0, 0.0, 0.0],
        **{
            descriptions[name]: [score, math.sqrt(1.0 - score * score), 0.0]
            for name, score in scores.items()
        },
    }
    package.joinpath('__init__.py').write_text(
        "import json, os\n"
        "import numpy as np\n"
        "from . import util\n"
        f"_VECTORS = {vectors!r}\n"
        "class SentenceTransformer:\n"
        "    def __init__(self, model_name_or_path=None, *args, **kwargs):\n"
        "        name = model_name_or_path if model_name_or_path is not None else kwargs.get('model_name')\n"
        "        if not isinstance(name, str) or not name.endswith('all-MiniLM-L6-v2'):\n"
        "            raise AssertionError('The pipeline did not request all-MiniLM-L6-v2')\n"
        "        with open(os.environ['ST_TEST_MARKER'], 'a') as f:\n"
        "            f.write(json.dumps({'model': name}) + '\\n')\n"
        "    def encode(self, sentences, convert_to_tensor=False, normalize_embeddings=False, **kwargs):\n"
        "        single = isinstance(sentences, str)\n"
        "        items = [sentences] if single else list(sentences)\n"
        "        rows = []\n"
        "        for text in items:\n"
        "            if text not in _VECTORS:\n"
        "                raise AssertionError('Pipeline encoded text not read from the test metadata/query: ' + repr(text))\n"
        "            rows.append(_VECTORS[text])\n"
        "        value = np.asarray(rows, dtype=float)\n"
        "        if normalize_embeddings:\n"
        "            value = value / np.linalg.norm(value, axis=1, keepdims=True)\n"
        "        if single:\n"
        "            value = value[0]\n"
        "        if convert_to_tensor:\n"
        "            import torch\n"
        "            return torch.tensor(value, dtype=torch.float32)\n"
        "        return value\n"
        "    def encode_query(self, sentences, **kwargs):\n"
        "        return self.encode(sentences, **kwargs)\n"
        "    def encode_document(self, sentences, **kwargs):\n"
        "        return self.encode(sentences, **kwargs)\n"
        "    def similarity(self, a, b):\n"
        "        return util.cos_sim(a, b)\n"
    )
    package.joinpath('util.py').write_text(
        "import numpy as np\n"
        "def _array(x):\n"
        "    if hasattr(x, 'detach'):\n"
        "        return x.detach().cpu().numpy()\n"
        "    return np.asarray(x, dtype=float)\n"
        "def cos_sim(a, b):\n"
        "    aa, bb = _array(a), _array(b)\n"
        "    if aa.ndim == 1: aa = aa.reshape(1, -1)\n"
        "    if bb.ndim == 1: bb = bb.reshape(1, -1)\n"
        "    aa = aa / np.linalg.norm(aa, axis=1, keepdims=True)\n"
        "    bb = bb / np.linalg.norm(bb, axis=1, keepdims=True)\n"
        "    import torch\n"
        "    return torch.tensor(aa @ bb.T, dtype=torch.float32)\n"
        "pytorch_cos_sim = cos_sim\n"
        "def semantic_search(query_embeddings, corpus_embeddings, top_k=10, **kwargs):\n"
        "    scores = cos_sim(query_embeddings, corpus_embeddings).cpu().numpy()\n"
        "    return [[{'corpus_id': int(i), 'score': float(row[i])} for i in np.argsort(-row)[:top_k]] for row in scores]\n"
    )


def test_pipeline_artifact_executes_and_computes_from_metadata():
    try:
        importlib.metadata.version('sentence-transformers')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail('sentence-transformers is not installed.')

    candidates = _candidate_scripts()
    assert candidates, 'No Python pipeline using sentence-transformers and all-MiniLM-L6-v2 was found.'

    descriptions = {
        f'dataset_{i:02d}.txt': f'Verifier synthetic metadata vector {i:02d}.'
        for i in range(1, 11)
    }
    scores = {
        'dataset_01.txt': 0.10,
        'dataset_02.txt': 0.20,
        'dataset_03.txt': 0.30,
        'dataset_04.txt': 0.90,
        'dataset_05.txt': 0.40,
        'dataset_06.txt': 0.50,
        'dataset_07.txt': 0.99,
        'dataset_08.txt': 0.60,
        'dataset_09.txt': 0.80,
        'dataset_10.txt': 0.00,
    }
    query_vector = [1.0, 0.0, 0.0]
    description_vectors = {
        name: [score, math.sqrt(1.0 - score * score), 0.0]
        for name, score in scores.items()
    }
    cosine = lambda a, b: sum(x*y for x, y in zip(a, b)) / (
        math.sqrt(sum(x*x for x in a)) * math.sqrt(sum(y*y for y in b))
    )
    expected = sorted(
        description_vectors,
        key=lambda name: cosine(query_vector, description_vectors[name]),
        reverse=True,
    )[:3]

    original_metadata = {p.name: p.read_bytes() for p in METADATA_DIR.glob('*.txt')}
    original_result = RESULT_PATH.read_bytes() if RESULT_PATH.exists() else None
    errors = []

    with tempfile.TemporaryDirectory() as temp:
        marker = Path(temp) / 'model_used.jsonl'
        _write_fake_sentence_transformers(temp, marker, descriptions, scores)
        env = os.environ.copy()
        env['PYTHONPATH'] = temp + os.pathsep + env.get('PYTHONPATH', '')
        env['ST_TEST_MARKER'] = str(marker)

        try:
            for script in candidates:
                for old in METADATA_DIR.glob('*.txt'):
                    old.unlink()
                for name, text in descriptions.items():
                    METADATA_DIR.joinpath(name).write_text(text)
                RESULT_PATH.unlink(missing_ok=True)
                marker.unlink(missing_ok=True)

                try:
                    run = subprocess.run(
                        [sys.executable, str(script)],
                        cwd=str(script.parent),
                        env=env,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        timeout=120,
                    )
                    if run.returncode != 0:
                        errors.append(f'{script}: exited {run.returncode}: {run.stdout[-1000:]}')
                        continue
                    if not marker.is_file():
                        errors.append(f'{script}: did not instantiate SentenceTransformer')
                        continue
                    result = json.loads(RESULT_PATH.read_text())
                    if result.get('query') != QUERY or result.get('top_3_files') != expected:
                        errors.append(f'{script}: produced {result!r}, expected top_3_files {expected!r}')
                        continue
                    return
                except Exception as exc:
                    errors.append(f'{script}: {exc!r}')
        finally:
            for current in METADATA_DIR.glob('*.txt'):
                current.unlink()
            for name, data in original_metadata.items():
                METADATA_DIR.joinpath(name).write_bytes(data)
            RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
            if original_result is None:
                RESULT_PATH.unlink(missing_ok=True)
            else:
                RESULT_PATH.write_bytes(original_result)

    pytest.fail('No submitted pipeline passed the execution test. ' + ' | '.join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
