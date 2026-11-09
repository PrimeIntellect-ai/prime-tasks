#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import ctypes
import itertools
import json
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest

EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
DETECTOR_SCRIPT = "/home/user/detector.py"
RESULTS_FILE = "/home/user/results.json"
RUST_PROJECT = "/home/user/rust_waf"
RUST_SO_PATH = "/home/user/rust_waf/target/release/librust_waf.so"
LEGACY_SCORER = "/app/legacy_scorer"


def run_detector(directory, env=None):
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, directory],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"detector.py failed on {directory}:\n{result.stderr}"
    assert os.path.isfile(RESULTS_FILE), f"Results file not created at {RESULTS_FILE}"
    try:
        with open(RESULTS_FILE, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("results.json is not valid JSON")
    assert isinstance(results, dict), "results.json must contain a JSON dictionary"
    return results


def test_rust_library_compiled():
    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(RUST_SO_PATH), f"Rust shared library not found at {RUST_SO_PATH}. Did you successfully run cargo build --release?"

    lib = ctypes.CDLL(RUST_SO_PATH)
    assert hasattr(lib, "compute_hazard"), "Shared library does not export compute_hazard"
    lib.compute_hazard.argtypes = [ctypes.c_char_p]
    lib.compute_hazard.restype = ctypes.c_uint32
    assert lib.compute_hazard(b"ordinary request") == 0
    assert lib.compute_hazard(b"SELECT UNION") == 1000
    assert lib.compute_hazard(b"SELECT UNION DROP") == 1500


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"


def test_detector_declares_ctypes_usage():
    with open(DETECTOR_SCRIPT, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=DETECTOR_SCRIPT)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "detector.py must use Python ctypes to load the Rust library"


def test_adversarial_corpus_evil():
    results = run_detector(EVIL_CORPUS_DIR)
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    bypassed = []
    for filepath in evil_files:
        if filepath not in results:
            bypassed.append(os.path.basename(filepath) + " (missing)")
        elif results[filepath] != "EVIL":
            bypassed.append(os.path.basename(filepath) + f" (scored as {results[filepath]})")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")


def test_adversarial_corpus_clean():
    results = run_detector(CLEAN_CORPUS_DIR)
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    modified = []
    for filepath in clean_files:
        if filepath not in results:
            modified.append(os.path.basename(filepath) + " (missing)")
        elif results[filepath] != "CLEAN":
            modified.append(os.path.basename(filepath) + f" (scored as {results[filepath]})")

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified (flagged as EVIL): {', '.join(modified)}")


def test_randomized_directory_against_legacy_engine():
    with tempfile.TemporaryDirectory(prefix="waf_hidden_") as corpus:
        nonce = uuid.uuid4().hex
        payloads = []
        keywords = ["SELECT", "UNION", "<script>", "DROP"]
        for index, mask in enumerate(itertools.product([False, True], repeat=4)):
            selected = [word for word, enabled in zip(keywords, mask) if enabled]
            payloads.append(f"neutral-{nonce}-{index} " + " separator ".join(selected))

        expected = {}
        for index, payload in enumerate(payloads):
            path = os.path.abspath(os.path.join(corpus, f"request_{uuid.uuid4().hex}_{index}.dat"))
            with open(path, "w", encoding="utf-8") as f:
                f.write(payload)
            legacy = subprocess.run([LEGACY_SCORER, payload], capture_output=True, text=True)
            assert legacy.returncode in (0, 1), f"Unexpected legacy scorer status {legacy.returncode}"
            expected[path] = "EVIL" if legacy.returncode == 1 else "CLEAN"

        results = run_detector(corpus)
        assert results == expected, "Detector did not classify the randomized corpus exactly as the legacy engine"


def test_detector_loads_and_calls_compute_hazard_with_exact_threshold():
    tokens = [uuid.uuid4().hex for _ in range(4)]
    shim_source = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void record_call(const char *payload) {
    const char *path = getenv("WAF_CALL_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fputs(payload, f);
    fputc('\n', f);
    fclose(f);
}

uint32_t compute_hazard(const char *payload) {
    if (!payload) return 0;
    record_call(payload);
    if (strstr(payload, %s)) return 1337;
    if (strstr(payload, %s)) return 1338;
    if (strstr(payload, %s)) return 0;
    if (strstr(payload, %s)) return 4000;
    return 777;
}
''' % tuple(json.dumps(token) for token in tokens)

    with tempfile.TemporaryDirectory(prefix="waf_ffi_test_") as tmp:
        source_path = os.path.join(tmp, "shim.c")
        shim_path = os.path.join(tmp, "librust_waf.so")
        backup_path = os.path.join(tmp, "real_librust_waf.so")
        call_log = os.path.join(tmp, "calls.log")
        ctypes_log = os.path.join(tmp, "ctypes.log")
        site_dir = os.path.join(tmp, "site")
        corpus = os.path.join(tmp, "random_input_" + uuid.uuid4().hex)
        os.mkdir(site_dir)
        os.mkdir(corpus)

        with open(source_path, "w", encoding="utf-8") as f:
            f.write(shim_source)
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", source_path, "-o", shim_path],
            capture_output=True,
            text=True,
        )
        assert compiled.returncode == 0, f"Failed to build verifier shim: {compiled.stderr}"

        sitecustomize = r'''
import ctypes
import os

_trace = os.environ.get("CTYPES_LOAD_LOG")
_original_cdll = ctypes.CDLL
_original_load_library = ctypes.LibraryLoader.LoadLibrary

def _write(name):
    if _trace:
        with open(_trace, "a") as f:
            f.write(str(name) + "\n")

def _traced_cdll(name, *args, **kwargs):
    _write(name)
    return _original_cdll(name, *args, **kwargs)

def _traced_load_library(self, name):
    _write(name)
    return _original_load_library(self, name)

ctypes.CDLL = _traced_cdll
ctypes.LibraryLoader.LoadLibrary = _traced_load_library
'''
        with open(os.path.join(site_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
            f.write(sitecustomize)

        payloads = [f"probe-{uuid.uuid4().hex}-{token}" for token in tokens]
        labels = ["CLEAN", "EVIL", "CLEAN", "EVIL"]
        expected = {}
        for payload, label in zip(payloads, labels):
            path = os.path.abspath(os.path.join(corpus, uuid.uuid4().hex + ".req"))
            with open(path, "w", encoding="utf-8") as f:
                f.write(payload)
            expected[path] = label

        shutil.copy2(RUST_SO_PATH, backup_path)
        env = os.environ.copy()
        env["WAF_CALL_LOG"] = call_log
        env["CTYPES_LOAD_LOG"] = ctypes_log
        env["PYTHONPATH"] = site_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        try:
            shutil.copy2(shim_path, RUST_SO_PATH)
            result = subprocess.run(
                ["python3", DETECTOR_SCRIPT, corpus],
                capture_output=True,
                text=True,
                env=env,
                timeout=30,
            )
            if os.path.isfile(RESULTS_FILE):
                try:
                    with open(RESULTS_FILE, "r") as f:
                        results = json.load(f)
                except json.JSONDecodeError:
                    results = None
            else:
                results = None
            ctypes_trace = open(ctypes_log).read() if os.path.isfile(ctypes_log) else ""
            calls = open(call_log).read().splitlines() if os.path.isfile(call_log) else []
        finally:
            shutil.copy2(backup_path, RUST_SO_PATH)

        assert result.returncode == 0, f"detector.py failed with instrumented Rust library:\n{result.stderr}"
        assert "librust_waf.so" in ctypes_trace, "detector.py did not load librust_waf.so through ctypes"
        assert results == expected, "Detector must treat score 1337 as CLEAN and score 1338 as EVIL and overwrite results.json"
        observed = collections.Counter(calls)
        for payload in payloads:
            assert observed[payload] >= 1, f"compute_hazard was not called with file payload {payload!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
