#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import random
import shutil
import string
import subprocess
import tempfile
from collections import Counter


def run_classifier(script_path, input_path, output_path):
    if os.path.exists(output_path):
        os.unlink(output_path)
    subprocess.run(
        ["python3", script_path, input_path, output_path],
        check=True,
        capture_output=True,
        timeout=5,
    )
    assert os.path.isfile(output_path), "Classifier did not create its output file"
    result = open(output_path, "r").read().strip()
    assert result in {"CLEAN", "EVIL"}, f"Invalid classifier output: {result!r}"
    return result


def expected_classification(document):
    graph = {}
    for edge in document.get("deps", []):
        source, target = edge
        graph.setdefault(source, []).append(target)
        graph.setdefault(target, [])

    visiting = set()
    visited = set()

    def has_cycle(node):
        if node in visiting:
            return True
        if node in visited:
            return False
        visiting.add(node)
        for neighbor in graph.get(node, []):
            if has_cycle(neighbor):
                return True
        visiting.remove(node)
        visited.add(node)
        return False

    cyclic = any(has_cycle(node) for node in list(graph))
    memory = document.get("mem", [])
    leaking = any(
        all(memory[j] < memory[j + 1] for j in range(start, start + 4))
        for start in range(max(0, len(memory) - 4))
    )
    return "EVIL" if cyclic or leaking else "CLEAN"


def test_rust_binary_compiled_and_run():
    project = "/app/dep-analyzer-core"
    binary_path = os.path.join(project, "target/release/dep-analyzer-core")
    output_log = "/home/user/rust_output.log"

    # Rebuild from the submitted source so a stale/prebuilt executable is insufficient.
    subprocess.run(["cargo", "clean"], cwd=project, check=True, capture_output=True, timeout=30)
    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=project,
        check=True,
        capture_output=True,
        timeout=120,
    )

    assert os.path.isfile(binary_path), f"Rust binary not found at {binary_path}. Did 'cargo build --release' succeed?"
    assert os.access(binary_path, os.X_OK), f"Rust binary at {binary_path} is not executable."
    assert os.path.isfile(output_log), f"Rust output log not found at {output_log}."
    assert os.path.getsize(output_log) > 0, f"Rust output log at {output_log} is empty."

    generated = subprocess.run(
        [binary_path, "--generate-samples"],
        cwd=project,
        check=True,
        capture_output=True,
        timeout=10,
    ).stdout
    with open(output_log, "rb") as handle:
        logged = handle.read()
    assert logged == generated, "rust_output.log is not the output produced by --generate-samples"
    assert generated.strip(), "--generate-samples produced no output"


def test_classifier_script_exists():
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script not found at {script_path}."


def test_adversarial_corpus_classification():
    script_path = "/home/user/classifier.py"
    assert os.path.isfile(script_path), f"Classifier script missing: {script_path}"

    evil_dir = "/home/user/corpora/evil"
    clean_dir = "/home/user/corpora/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))

    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"

    evil_bypassed = []
    clean_modified = []
    with tempfile.TemporaryDirectory() as tmpdir:
        temp_out = os.path.join(tmpdir, "out.txt")
        for evil_file in evil_files:
            try:
                if run_classifier(script_path, evil_file, temp_out) != "EVIL":
                    evil_bypassed.append(os.path.basename(evil_file))
            except Exception:
                evil_bypassed.append(os.path.basename(evil_file))

        for clean_file in clean_files:
            try:
                if run_classifier(script_path, clean_file, temp_out) != "CLEAN":
                    clean_modified.append(os.path.basename(clean_file))
            except Exception:
                clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)


def test_classifier_on_generated_inputs_with_neutral_paths():
    script_path = "/home/user/classifier.py"
    rng = random.SystemRandom()

    def node():
        return "n" + "".join(rng.choice(string.ascii_letters) for _ in range(12))

    cases = []
    for _ in range(4):
        a, b, c, d, e = [node() for _ in range(5)]
        cases.extend([
            {"deps": [[a, b], [a, c], [b, d], [c, e]], "mem": [30, 31, 32, 33, 10, 11]},
            {"deps": [[a, b], [b, c], [c, a]], "mem": [50, 20, 40, 10]},
            {"deps": [[a, a]], "mem": [9, 4, 8]},
            {"deps": [[a, b], [c, d]], "mem": [rng.randrange(1, 20) + x for x in range(6)]},
            {"deps": [[a, b], [b, c]], "mem": [80, 40, 41, 42, 43, 44, 45]},
            {"deps": [], "mem": [10, 9, 8, 7, 6, 5]},
        ])

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="artifact_inputs_") as tmpdir:
        output_path = os.path.join(tmpdir, "classification.txt")
        for document in cases:
            filename = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(20)) + ".json"
            input_path = os.path.join(tmpdir, filename)
            with open(input_path, "w") as handle:
                json.dump(document, handle)
            actual = run_classifier(script_path, input_path, output_path)
            assert actual == expected_classification(document), (
                f"Wrong classification for generated JSON {document}: expected "
                f"{expected_classification(document)}, got {actual}"
            )


def test_csv_results_exist():
    csv_path = "/home/user/classification_results.csv"
    assert os.path.isfile(csv_path), f"Classification results CSV not found at {csv_path}."
    with open(csv_path, "r") as handle:
        rows = list(csv.reader(handle))
    assert len(rows) > 0, "Classification results CSV is empty."


def test_run_eval_exists_and_functions():
    run_eval = "/home/user/run_eval.sh"
    classifier = "/home/user/classifier.py"
    real_classifier = "/home/user/classifier.py.verifier-real"
    calls_file = "/tmp/classifier_calls.log"
    csv_path = "/home/user/classification_results.csv"

    assert os.path.isfile(run_eval), f"Summary script not found at {run_eval}."
    corpus_files = sorted(
        glob.glob("/home/user/corpora/clean/*.json")
        + glob.glob("/home/user/corpora/evil/*.json")
    )
    assert corpus_files

    expected_rows = []
    for path in corpus_files:
        with open(path, "r") as handle:
            expected_rows.append((os.path.basename(path), expected_classification(json.load(handle))))

    if os.path.exists(calls_file):
        os.unlink(calls_file)
    if os.path.exists(csv_path):
        os.unlink(csv_path)

    os.rename(classifier, real_classifier)
    try:
        with open(classifier, "w") as wrapper:
            wrapper.write("#!/usr/bin/env python3\n")
            wrapper.write("import subprocess, sys\n")
            wrapper.write(f"with open({calls_file!r}, 'a') as f: f.write(sys.argv[1] + '\\n')\n")
            wrapper.write(f"raise SystemExit(subprocess.call([sys.executable, {real_classifier!r}] + sys.argv[1:]))\n")
        os.chmod(classifier, 0o755)
        subprocess.run(
            ["bash", run_eval],
            cwd="/home/user",
            check=True,
            capture_output=True,
            timeout=60,
        )
    finally:
        if os.path.exists(classifier):
            os.unlink(classifier)
        os.rename(real_classifier, classifier)

    assert os.path.isfile(calls_file), "run_eval.sh did not invoke classifier.py"
    called = [os.path.realpath(line.strip()) for line in open(calls_file) if line.strip()]
    assert Counter(called) == Counter(map(os.path.realpath, corpus_files)), (
        "run_eval.sh must invoke classifier.py exactly once for every corpus JSON file"
    )

    assert os.path.isfile(csv_path), "run_eval.sh did not create classification_results.csv"
    with open(csv_path, newline="") as handle:
        rows = list(csv.reader(handle))
    assert all(len(row) == 2 for row in rows), "Each CSV row must contain filename,classification"
    assert Counter(map(tuple, rows)) == Counter(expected_rows), (
        "classification_results.csv must contain exactly one correctly classified row for every corpus file"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
