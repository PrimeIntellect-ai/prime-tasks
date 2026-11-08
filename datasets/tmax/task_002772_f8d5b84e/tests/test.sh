#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/filter_records.py"
CLEAN_CORPUS = "/app/clean_corpus"
EVIL_CORPUS = "/app/evil_corpus"
REFERENCE_QUERY = "neural network architectures"


def run_script(input_dir, output_dir, *extra):
    return subprocess.run(
        ["python3", SCRIPT_PATH, "--input-dir", input_dir, "--output-dir", output_dir, *extra],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Agent's script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Agent's script is not executable: {SCRIPT_PATH}"


def test_required_python_api_is_present():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=SCRIPT_PATH)

    referenced = set()
    string_literals = set()
    argument_options = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            referenced.add(node.id)
        elif isinstance(node, ast.Attribute):
            referenced.add(node.attr)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            string_literals.add(node.value)
        elif isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else (
                node.func.id if isinstance(node.func, ast.Name) else ""
            )
            if name == "add_argument":
                for arg in node.args:
                    if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                        argument_options.add(arg.value)

    assert "ArgumentParser" in referenced, "The script must use argparse.ArgumentParser"
    assert {"--input-dir", "--output-dir"}.issubset(argument_options), "Required argparse options are missing"
    assert "TfidfVectorizer" in referenced, "The script must use TfidfVectorizer"
    assert "cosine_similarity" in referenced, "The script must use cosine_similarity"
    assert "english" in string_literals, "TfidfVectorizer must be configured with stop_words='english'"


def test_filter_clean_corpus():
    with tempfile.TemporaryDirectory() as out_dir:
        result = run_script(CLEAN_CORPUS, out_dir)
        assert result.returncode == 0, f"Script failed on clean corpus. stderr: {result.stderr}"

        expected_files = set(os.listdir(CLEAN_CORPUS))
        actual_files = set(os.listdir(out_dir))

        missing = expected_files - actual_files
        assert not missing, f"{len(missing)} of {len(expected_files)} clean files rejected (should be accepted). Missing: {missing}"


def test_filter_evil_corpus():
    with tempfile.TemporaryDirectory() as out_dir:
        result = run_script(EVIL_CORPUS, out_dir)
        assert result.returncode == 0, f"Script failed on evil corpus. stderr: {result.stderr}"

        actual_files = set(os.listdir(out_dir))
        expected_files = set(os.listdir(EVIL_CORPUS))

        assert not actual_files, f"{len(actual_files)} of {len(expected_files)} evil files bypassed (should be rejected). Bypassed: {actual_files}"


def required_score(document):
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity

    vectors = TfidfVectorizer(stop_words="english").fit_transform([REFERENCE_QUERY, document])
    return float(cosine_similarity(vectors[0:1], vectors[1:2])[0, 0])


def test_randomized_mixed_corpus_uses_required_similarity_and_threshold():
    nonce = secrets.token_hex(8)
    documents = {
        f"exact_{nonce}.txt": REFERENCE_QUERY,
        f"unrelated_{nonce}.txt": "sourdough fermentation starter temperature baking",
        f"network_{nonce}.txt": "network routing packets switches infrastructure",
        f"architectures_{nonce}.txt": "architectures monuments columns masonry heritage",
    }

    # These documents straddle the 0.05 boundary under the required per-document
    # two-item TF-IDF fit. Random tokens and filenames prevent path/content lookup.
    for count in range(28, 65, 3):
        fillers = " ".join(f"token{nonce}{count}x{i}" for i in range(count))
        documents[f"boundary_{nonce}_{count}.txt"] = f"neural {fillers}"

    expected = {name for name, text in documents.items() if required_score(text) > 0.05}
    rejected = set(documents) - expected
    assert expected and rejected, "Verifier corpus must exercise both sides of the threshold"

    with tempfile.TemporaryDirectory(prefix=f"corpus_{nonce}_") as input_dir:
        output_dir = os.path.join(tempfile.gettempdir(), f"filtered_{nonce}")
        if os.path.exists(output_dir):
            raise AssertionError(f"Unexpected pre-existing output path: {output_dir}")

        for name, text in documents.items():
            with open(os.path.join(input_dir, name), "w", encoding="utf-8") as fh:
                fh.write(text)
        with open(os.path.join(input_dir, f"ignored_{nonce}.md"), "w", encoding="utf-8") as fh:
            fh.write(REFERENCE_QUERY)

        try:
            result = run_script(input_dir, output_dir)
            assert result.returncode == 0, f"Script failed on randomized corpus. stderr: {result.stderr}"
            assert os.path.isdir(output_dir), "Script did not create the requested output directory"

            actual = set(os.listdir(output_dir))
            assert actual == expected, f"Incorrect randomized filtering. Expected {expected}, got {actual}"

            for name in expected:
                with open(os.path.join(output_dir, name), "r", encoding="utf-8") as fh:
                    assert fh.read() == documents[name], f"Copied content changed for {name}"
        finally:
            if os.path.isdir(output_dir):
                import shutil
                shutil.rmtree(output_dir)


def test_argparse_rejects_missing_and_unknown_arguments():
    missing = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    assert missing.returncode != 0, "Both required command-line arguments must be enforced"

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        unknown = run_script(input_dir, output_dir, "--unexpected-option")
        assert unknown.returncode != 0, "Unexpected command-line arguments must be rejected by argparse"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
