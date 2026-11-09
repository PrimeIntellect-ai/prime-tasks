#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest


def assert_healthy_server(binary):
    proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 3
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"{binary} exited before serving requests on port 8080")
            try:
                with urllib.request.urlopen("http://localhost:8080/health", timeout=0.5) as response:
                    assert response.status == 200, f"Expected status 200, got {response.status}"
                    assert response.read().decode().strip() == "OK"
                    return
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        pytest.fail(f"Failed to connect to {binary} on port 8080: {last_error}")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def test_modproxy_binary():
    bin_path = "/home/user/modproxy-bin"
    assert os.path.isfile(bin_path), f"Fixed proxy binary not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Binary at {bin_path} is not executable"
    assert_healthy_server(bin_path)


def test_modproxy_source_and_makefile():
    source_dir = "/app/vendored/modproxy"
    main_go = os.path.join(source_dir, "main.go")
    makefile = os.path.join(source_dir, "Makefile")
    assert os.path.isfile(main_go), "Vendored modproxy main.go is missing"
    assert os.path.isfile(makefile), "Vendored modproxy Makefile is missing"

    make_text = open(makefile, encoding="utf-8").read()
    assert re.search(r"\bGO111MODULE\s*=\s*on\b", make_text), \
        "Makefile does not set GO111MODULE=on"
    assert re.search(r"\bgo\s+build\b", make_text), "Makefile does not invoke go build"

    with tempfile.TemporaryDirectory() as td:
        build_dir = os.path.join(td, "modproxy")
        shutil.copytree(source_dir, build_dir, ignore=shutil.ignore_patterns("modproxy-bin"))
        subprocess.run(["make", "-B", "build"], cwd=build_dir, timeout=30, check=True)

        source_binary = os.path.join(td, "modproxy-from-source")
        env = os.environ.copy()
        env["GO111MODULE"] = "on"
        subprocess.run(
            ["go", "build", "-o", source_binary, "main.go"],
            cwd=build_dir,
            env=env,
            timeout=30,
            check=True,
        )
        assert_healthy_server(source_binary)


def parse_classifier_output(text, expected_names):
    results = {}
    counts = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = re.fullmatch(r"\[?([^\[\]:]+\.json)\]?\s*:\s*(CLEAN|EVIL)", line)
        assert match, f"Malformed classifier output line: {line!r}"
        name, result = match.groups()
        results[name] = result
        counts[name] = counts.get(name, 0) + 1

    assert set(results) == set(expected_names), \
        f"Classifier returned filenames {sorted(results)}, expected {sorted(expected_names)}"
    assert all(counts[name] == 1 for name in expected_names), \
        "Classifier must output exactly one line per JSON file"
    return results


def exercise_classifier(binary):
    token = uuid.uuid4().hex
    cases = []

    def add(label, requested, minimum, payload, checksum, depth, expected):
        name = f"{token}_{label}.json"
        cases.append((name, {
            "package_name": f"pkg-{token}-{label}",
            "requested_version": requested,
            "minimum_required_version": minimum,
            "package_payload": payload,
            "sha256_checksum": checksum,
            "graph_depth": depth,
        }, expected))

    payload_clean = f"clean-{token}"
    add("clean", "v2.10.0", "v2.9.9", payload_clean,
        hashlib.sha256(payload_clean.encode()).hexdigest(), 10, "CLEAN")

    payload_down = f"down-{token}"
    add("downgrade", "v3.9.9", "v3.10.0", payload_down,
        hashlib.sha256(payload_down.encode()).hexdigest(), 2, "EVIL")

    payload_hash = f"hash-{token}"
    add("checksum", "v4.2.0", "v4.1.0", payload_hash, "0" * 64, 4, "EVIL")

    payload_depth = f"depth-{token}"
    add("depth", "v5.0.0", "v5.0.0", payload_depth,
        hashlib.sha256(payload_depth.encode()).hexdigest(), 11, "EVIL")

    log_path = "/home/user/classification.log"
    old_log_exists = os.path.exists(log_path)
    old_log = open(log_path, "rb").read() if old_log_exists else None

    try:
        if os.path.exists(log_path):
            os.remove(log_path)
        with tempfile.TemporaryDirectory() as corpus:
            for name, document, _ in cases:
                with open(os.path.join(corpus, name), "w", encoding="utf-8") as handle:
                    json.dump(document, handle)

            completed = subprocess.run(
                [binary, corpus],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
                check=True,
            )

            if os.path.isfile(log_path) and os.path.getsize(log_path) > 0:
                output = open(log_path, encoding="utf-8").read()
            else:
                output = completed.stdout

            expected = {name: result for name, _, result in cases}
            actual = parse_classifier_output(output, expected)
            assert actual == expected, f"Incorrect classifications: {actual}; expected {expected}"
    finally:
        if old_log_exists:
            with open(log_path, "wb") as handle:
                handle.write(old_log)
        elif os.path.exists(log_path):
            os.remove(log_path)


def test_security_filter_binary_and_source_on_derived_inputs():
    bin_path = "/home/user/secfilter-bin"
    source_path = "/home/user/secfilter/main.go"
    assert os.path.isfile(bin_path), f"Classifier binary not found at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Classifier binary at {bin_path} is not executable"
    with open(bin_path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "secfilter-bin is not a compiled executable"
    assert os.path.isfile(source_path), f"Classifier source not found at {source_path}"

    exercise_classifier(bin_path)

    with tempfile.TemporaryDirectory() as td:
        source_binary = os.path.join(td, "secfilter-from-source")
        subprocess.run(
            ["go", "build", "-o", source_binary, source_path],
            cwd="/home/user/secfilter",
            timeout=30,
            check=True,
        )
        exercise_classifier(source_binary)


def test_e2e_script_and_classification_log():
    script_path = "/home/user/run_e2e.sh"
    log_path = "/home/user/classification.log"

    assert os.path.isfile(script_path), f"End-to-end script not found at {script_path}"
    if os.path.exists(log_path):
        os.remove(log_path)

    try:
        subprocess.run(["bash", script_path], timeout=15, check=True)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {script_path} timed out after 15 seconds.")
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Execution of {script_path} failed with exit code {exc.returncode}.")

    assert os.path.isfile(log_path), f"Classification log not found at {log_path}. Ensure your classifier writes to it."

    with open(log_path, "r") as handle:
        log_lines = [line.strip() for line in handle if line.strip()]

    log_dict = {}
    for line in log_lines:
        parts = line.split(":")
        if len(parts) >= 2:
            fname = parts[0].strip()
            res = parts[1].strip()
            log_dict[fname] = res

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = os.listdir(clean_dir) if os.path.exists(clean_dir) else []
    evil_files = os.listdir(evil_dir) if os.path.exists(evil_dir) else []

    clean_modified = [name for name in clean_files if log_dict.get(name) != "CLEAN"]
    evil_bypassed = [name for name in evil_files if log_dict.get(name) != "EVIL"]

    err_msgs = []
    if evil_bypassed:
        err_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        err_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if err_msgs:
        pytest.fail(" | ".join(err_msgs))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
