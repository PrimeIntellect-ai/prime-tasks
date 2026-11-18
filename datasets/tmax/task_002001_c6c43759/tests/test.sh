#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import importlib.util
import inspect
import json
import math
import os
import subprocess
import sys
import tempfile

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
HEADERS_VALID = {"X-API-Key": "ml-data-secret"}
HEADERS_INVALID = {"X-API-Key": "wrong"}
PACKAGE_DIR = "/app/bio-feature-extractor"


def expected_features(mol_id):
    with open("/home/user/raw_data.json", "r") as f:
        data = json.load(f)

    mol_data = next((item for item in data if item["id"] == mol_id), None)
    if not mol_data:
        pytest.fail(f"Could not find {mol_id} in /home/user/raw_data.json")

    # These are the independently derived semantics of the supplied C package.
    return len(mol_data["adj"]) * 0.5, len(mol_data["seq"].encode("utf-8")) * 2.0


def assert_numeric_close(actual, expected, name):
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"{name} must be numeric"
    assert math.isfinite(actual), f"{name} must be finite"
    assert math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-8), f"Expected {name} {expected}, got {actual}"


def test_installed_package_is_compiled_and_correct_on_held_out_inputs():
    try:
        import bio_feature_extractor
    except ImportError:
        pytest.fail("Failed to import bio_feature_extractor. The package was not installed correctly.")

    origin = getattr(bio_feature_extractor, "__file__", "") or ""
    assert origin.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)), (
        f"bio_feature_extractor must be an installed compiled extension, got {origin!r}"
    )
    assert inspect.isbuiltin(bio_feature_extractor.compute_spectral_gap)
    assert inspect.isbuiltin(bio_feature_extractor.local_alignment)

    adjacency_cases = [[], [[]], [[1], [0]], [[], [], [], [], []], [[] for _ in range(11)]]
    for adj in adjacency_cases:
        result = bio_feature_extractor.compute_spectral_gap(adj)
        assert_numeric_close(result, len(adj) * 0.5, "compute_spectral_gap result")

    sequence_cases = ["", "A", "TACT", "CCGGAATTCC", "GATTACAGATTACA"]
    motifs = ["GATTACA", "T", "CCCC", "", "ACA"]
    for seq, motif in zip(sequence_cases, motifs):
        result = bio_feature_extractor.local_alignment(seq, motif)
        assert_numeric_close(result, len(seq.encode("utf-8")) * 2.0, "local_alignment result")


def test_vendored_package_now_builds_and_built_artifact_works():
    assert os.path.isfile(os.path.join(PACKAGE_DIR, "setup.py")), "Vendored setup.py is missing"
    assert os.path.isfile(os.path.join(PACKAGE_DIR, "src", "fast_align.c")), "Vendored C source is missing"

    with tempfile.TemporaryDirectory() as td:
        build_lib = os.path.join(td, "lib")
        build_temp = os.path.join(td, "temp")
        proc = subprocess.run(
            [sys.executable, "setup.py", "build_ext", "--force", "--build-lib", build_lib, "--build-temp", build_temp],
            cwd=PACKAGE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
        assert proc.returncode == 0, f"Vendored package still fails to compile:\n{proc.stdout}"

        artifacts = []
        for suffix in importlib.machinery.EXTENSION_SUFFIXES:
            artifacts.extend(glob.glob(os.path.join(build_lib, "**", "bio_feature_extractor*" + suffix), recursive=True))
        assert artifacts, f"Building the vendored package produced no compiled extension. Output:\n{proc.stdout}"

        probe = r'''
import importlib.util, inspect, math, sys
path = sys.argv[1]
spec = importlib.util.spec_from_file_location("bio_feature_extractor", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert inspect.isbuiltin(module.compute_spectral_gap)
assert inspect.isbuiltin(module.local_alignment)
for n in (0, 1, 3, 7, 13):
    value = module.compute_spectral_gap([[] for _ in range(n)])
    assert math.isclose(value, n * 0.5, rel_tol=1e-12, abs_tol=1e-12), (n, value)
for seq, motif in (("", "GATTACA"), ("AC", "Z"), ("TTGCA", "ACA"), ("A" * 17, "GATTACA")):
    value = module.local_alignment(seq, motif)
    assert math.isclose(value, len(seq.encode("utf-8")) * 2.0, rel_tol=1e-12, abs_tol=1e-12), (seq, value)
'''
        probe_proc = subprocess.run(
            [sys.executable, "-c", probe, artifacts[0]],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert probe_proc.returncode == 0, f"Freshly built extension has incorrect behavior:\n{probe_proc.stdout}"


def test_health_valid_auth():
    try:
        resp = requests.get(f"{BASE_URL}/health", headers=HEADERS_VALID, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/health: {e}")

    assert resp.status_code == 200, f"Expected 200 OK for /health with valid auth, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except Exception:
        pytest.fail(f"Response from /health is not valid JSON. Response text: {resp.text}")
    assert data.get("status") == "ok", f"Expected status: ok in /health response, got: {data.get('status')}"


def test_health_invalid_auth():
    try:
        resp = requests.get(f"{BASE_URL}/health", headers=HEADERS_INVALID, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/health: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for /health with invalid auth, got {resp.status_code}. Response: {resp.text}"


def test_health_missing_auth():
    try:
        resp = requests.get(f"{BASE_URL}/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/health: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for /health with missing auth, got {resp.status_code}. Response: {resp.text}"


@pytest.mark.parametrize("mol_id", ["mol_1", "mol_2"])
def test_feature_records(mol_id):
    expected_gap, expected_score = expected_features(mol_id)
    try:
        resp = requests.get(f"{BASE_URL}/feature/{mol_id}", headers=HEADERS_VALID, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/feature/{mol_id}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK for /feature/{mol_id}, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except Exception:
        pytest.fail(f"Response from /feature/{mol_id} is not valid JSON. Response text: {resp.text}")

    assert data.get("id") == mol_id, f"Expected id to be {mol_id!r}, got {data.get('id')}"
    assert "spectral_gap" in data, "Missing 'spectral_gap' in response"
    assert "alignment_score" in data, "Missing 'alignment_score' in response"
    assert_numeric_close(data["spectral_gap"], expected_gap, "spectral_gap")
    assert_numeric_close(data["alignment_score"], expected_score, "alignment_score")


def test_feature_unknown_mol():
    try:
        resp = requests.get(f"{BASE_URL}/feature/unknown_mol", headers=HEADERS_VALID, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/feature/unknown_mol: {e}")
    assert resp.status_code == 404, f"Expected 404 Not Found for /feature/unknown_mol, got {resp.status_code}. Response: {resp.text}"


def test_feature_invalid_auth():
    try:
        resp = requests.get(f"{BASE_URL}/feature/mol_1", headers=HEADERS_INVALID, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/feature/mol_1: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for /feature/mol_1 with invalid auth, got {resp.status_code}. Response: {resp.text}"


def test_feature_missing_auth():
    try:
        resp = requests.get(f"{BASE_URL}/feature/mol_1", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/feature/mol_1: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized for /feature/mol_1 with missing auth, got {resp.status_code}. Response: {resp.text}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
