#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess
from pathlib import Path


def test_gcc_make_installed():
    assert shutil.which("gcc") is not None, "gcc is not installed or not in PATH."
    assert shutil.which("make") is not None, "make is not installed or not in PATH."


def test_c_source_exists():
    path = "/home/user/src/search.c"
    assert os.path.isfile(path), f"C source file {path} does not exist."


def test_executable_exists():
    path = "/home/user/src/search"
    assert os.path.isfile(path), f"Compiled executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_output_file_exists():
    path = "/home/user/output/results.csv"
    assert os.path.isfile(path), f"Output file {path} does not exist."


def test_output_file_content():
    path = "/home/user/output/results.csv"
    expected_lines = [
        "id,similarity",
        "2,0.8944",
        "4,0.7746",
        "5,0.7746"
    ]

    with open(path, "r") as f:
        content = f.read().strip().split("\n")

    assert len(content) == len(expected_lines), f"Output file should have {len(expected_lines)} lines, but has {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual.strip()}'."


def _expected_output(vocab, documents):
    vocab_index = {word: i for i, word in enumerate(vocab)}

    def vector(text):
        counts = [0] * len(vocab)
        for token in text.split(" "):
            if token in vocab_index:
                counts[vocab_index[token]] += 1
        return counts

    vectors = {doc_id: vector(text) for doc_id, text in documents}
    query = vectors[1]
    query_norm = math.sqrt(sum(value * value for value in query))
    scored = []

    for doc_id, _ in documents:
        if doc_id == 1:
            continue
        candidate = vectors[doc_id]
        candidate_norm = math.sqrt(sum(value * value for value in candidate))
        if query_norm == 0.0 or candidate_norm == 0.0:
            similarity = 0.0
        else:
            dot = sum(a * b for a, b in zip(query, candidate))
            similarity = dot / (query_norm * candidate_norm)
        scored.append((doc_id, similarity))

    scored.sort(key=lambda item: (-item[1], item[0]))
    return ["id,similarity"] + [f"{doc_id},{similarity:.4f}" for doc_id, similarity in scored[:3]]


def _run_case(executable, vocab, documents, remove_output_directory=False):
    data_dir = Path("/home/user/data")
    output_dir = Path("/home/user/output")
    output_path = output_dir / "results.csv"

    (data_dir / "vocab.txt").write_text("\n".join(vocab) + "\n")
    dataset = "id,text\n" + "".join(f"{doc_id},{text}\n" for doc_id, text in documents)
    (data_dir / "dataset.csv").write_text(dataset)

    if remove_output_directory:
        shutil.rmtree(output_dir, ignore_errors=True)
    else:
        output_dir.mkdir(parents=True, exist_ok=True)
        if output_path.exists():
            output_path.unlink()

    result = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Submitted executable failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert output_path.is_file(), "Executable did not create /home/user/output/results.csv."

    actual = [line.strip() for line in output_path.read_text().strip().splitlines()]
    expected = _expected_output(vocab, documents)
    assert actual == expected, f"Dynamic input produced {actual!r}, expected {expected!r}."


def test_source_compiles_and_executable_processes_changed_inputs():
    source = Path("/home/user/src/search.c")
    executable = Path("/home/user/src/search")
    dataset_path = Path("/home/user/data/dataset.csv")
    vocab_path = Path("/home/user/data/vocab.txt")
    output_dir = Path("/home/user/output")
    output_path = output_dir / "results.csv"

    original_dataset = dataset_path.read_bytes()
    original_vocab = vocab_path.read_bytes()
    original_output = output_path.read_bytes()

    try:
        compile_result = subprocess.run(
            ["gcc", "-O3", str(source), "-o", str(executable), "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"search.c did not compile successfully. stdout: {compile_result.stdout!r}; "
            f"stderr: {compile_result.stderr!r}"
        )
        assert executable.is_file() and os.access(executable, os.X_OK)

        _run_case(
            executable,
            ["alpha", "beta", "gamma", "delta"],
            [
                (1, "alpha alpha beta gamma"),
                (10, "alpha beta"),
                (2, "alpha alpha beta gamma"),
                (7, "delta delta"),
                (3, "beta gamma"),
                (20, "alpha alpha"),
            ],
            remove_output_directory=True,
        )

        _run_case(
            executable,
            ["one", "two", "three", "four"],
            [
                (1, "one two"),
                (9, "one"),
                (3, "two"),
                (12, "one two"),
                (4, "three four"),
                (15, "two"),
            ],
        )
    finally:
        dataset_path.parent.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        dataset_path.write_bytes(original_dataset)
        vocab_path.write_bytes(original_vocab)
        output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
