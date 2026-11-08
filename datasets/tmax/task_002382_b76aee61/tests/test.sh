#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib
import json
import math
import os
import re
import subprocess

import pytest

PIPELINE = "/home/user/pipeline"
DATASET = os.path.join(PIPELINE, "massive_data.yaml")
RESULTS = os.path.join(PIPELINE, "benchmark_results.json")
BENCHMARK = os.path.join(PIPELINE, "run_benchmark.py")
VENDORED = os.path.realpath("/app/vendored/pyyaml-6.0.1")

EXPECTED_BENCHMARK = '''import sys
import time
import json
import yaml

try:
    from yaml import CSafeLoader as Loader
except ImportError:
    from yaml import SafeLoader as Loader

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    dataset = sys.argv[1]

    start = time.time()
    with open(dataset, 'r') as f:
        data = yaml.load(f, Loader=Loader)
    end = time.time()

    elapsed = end - start
    with open("benchmark_results.json", "w") as f:
        json.dump({"time_taken": elapsed}, f)

if __name__ == "__main__":
    main()
'''


def expected_dataset_digest():
    digest = hashlib.sha256()
    size = 0
    for i in range(100000):
        chunk = (
            f"- id: {i}\n"
            "  nested:\n"
            "    a: 1\n"
            "    b:\n"
            "    - 1\n"
            "    - 2\n"
            "    - 3\n"
            f"  value: item_{i}\n"
        ).encode("utf-8")
        digest.update(chunk)
        size += len(chunk)
    return digest.hexdigest(), size


def test_massive_data_recovered():
    assert os.path.exists(DATASET), f"{DATASET} was not recovered."
    assert os.path.isfile(DATASET), f"{DATASET} is not a regular file."

    expected_hash, expected_size = expected_dataset_digest()
    actual = hashlib.sha256()
    with open(DATASET, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            actual.update(chunk)

    assert os.path.getsize(DATASET) == expected_size, "Recovered dataset has the wrong size."
    assert actual.hexdigest() == expected_hash, "Recovered dataset is not the exact deleted YAML data."

    blob_id = subprocess.check_output(
        ["git", "-C", PIPELINE, "hash-object", DATASET], text=True
    ).strip()
    object_type = subprocess.check_output(
        ["git", "-C", PIPELINE, "cat-file", "-t", blob_id], text=True
    ).strip()
    assert object_type == "blob", "The recovered data does not match the Git blob stored in the repository."

    blob = subprocess.Popen(
        ["git", "-C", PIPELINE, "cat-file", "blob", blob_id],
        stdout=subprocess.PIPE,
    )
    blob_digest = hashlib.sha256()
    assert blob.stdout is not None
    for chunk in iter(lambda: blob.stdout.read(1024 * 1024), b""):
        blob_digest.update(chunk)
    assert blob.wait() == 0
    assert blob_digest.hexdigest() == expected_hash, "The Git blob contents do not match the recovered file."


def test_c_extension_available_and_vendored_install_is_repaired():
    try:
        import yaml
        from yaml import CSafeLoader
        yaml_ext = importlib.import_module("yaml._yaml")
    except ImportError as exc:
        pytest.fail(f"yaml.CSafeLoader could not be imported: {exc}")

    assert getattr(yaml, "__with_libyaml__", False), "PyYAML reports that libyaml support is disabled."
    assert CSafeLoader.__module__ == "yaml.cyaml", "CSafeLoader is not the C-backed loader."

    yaml_path = os.path.realpath(yaml.__file__)
    extension_path = os.path.realpath(yaml_ext.__file__)
    assert os.path.commonpath([yaml_path, VENDORED]) == VENDORED, \
        f"Imported PyYAML is not the vendored installation: {yaml_path}"
    assert os.path.commonpath([extension_path, VENDORED]) == VENDORED, \
        f"The loaded C extension was not built from the vendored package: {extension_path}"

    setup_path = os.path.join(VENDORED, "setup.py")
    with open(setup_path, "r", encoding="utf-8") as stream:
        setup_source = stream.read()
    assert not re.search(r"(?m)^\s*with_libyaml\s*=\s*False\b", setup_source), \
        "The vendored setup.py still hardcodes with_libyaml=False."


def test_benchmark_results_and_metric():
    with open(BENCHMARK, "r", encoding="utf-8") as stream:
        assert stream.read() == EXPECTED_BENCHMARK, "The provided benchmark script was modified."

    if os.path.lexists(RESULTS):
        os.unlink(RESULTS)

    completed = subprocess.run(
        ["python3", "-I", BENCHMARK, DATASET],
        cwd=PIPELINE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, \
        f"Benchmark execution failed.\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    assert os.path.exists(RESULTS), f"{RESULTS} does not exist after running the benchmark script."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a regular file."

    with open(RESULTS, "r", encoding="utf-8") as stream:
        try:
            data = json.load(stream)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {RESULTS} as valid JSON.")

    assert "time_taken" in data, f"'time_taken' key not found in {RESULTS}."
    time_taken = data["time_taken"]
    assert isinstance(time_taken, (int, float)) and not isinstance(time_taken, bool), \
        "'time_taken' must be a number."
    assert math.isfinite(time_taken) and time_taken >= 0, "'time_taken' must be a finite nonnegative number."
    assert time_taken < 0.5, \
        f"Execution time metric failed: expected < 0.5 seconds, got {time_taken} seconds."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
