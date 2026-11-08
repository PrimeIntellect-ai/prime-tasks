#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import runpy
import struct
import subprocess
import sys
import tempfile
import uuid
from unittest.mock import patch

import pytest

PROJECT = "/app/vendor/quant-db-1.2.0"

AGGREGATION_CHECK = r'''
import importlib.machinery
import importlib.util
import math
import random
import sys

mode, target = sys.argv[1], sys.argv[2]
if mode == "installed":
    import importlib.metadata
    assert importlib.metadata.version("quant-db") == "1.2.0"
    import quant_db.aggregator as module
    assert any(module.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), module.__file__
else:
    spec = importlib.util.spec_from_file_location("aggregator", target)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

rng = random.SystemRandom()
n = rng.randrange(350000, 550001)
values = [0.1] * n
expected = math.fsum(values)
actual = module.aggregate(values)
assert isinstance(actual, float)
assert abs(actual - expected) < 0.002, (actual, expected)

values = [rng.uniform(-1.0, 1.0) for _ in range(20000)]
expected = math.fsum(values)
actual = module.aggregate(values)
assert abs(actual - expected) < 1e-8, (actual, expected)
'''


def test_quant_db_installed_and_fixed():
    """Keep the shipped test, then independently exercise installed and rebuilt extensions."""
    test_file = os.path.join(PROJECT, "tests/test_agg.py")
    assert os.path.isfile(test_file), f"Test file {test_file} is missing"

    result = subprocess.run(
        ["pytest", test_file], capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f"quant-db tests failed:\n{result.stdout}\n{result.stderr}"

    setup_file = os.path.join(PROJECT, "setup.py")
    captured = {}
    old_cwd = os.getcwd()
    try:
        os.chdir(PROJECT)
        with patch("setuptools.setup", side_effect=lambda **kw: captured.update(kw)):
            runpy.run_path(setup_file, run_name="__main__")
    finally:
        os.chdir(old_cwd)

    extensions = captured.get("ext_modules") or []
    assert extensions, "setup.py does not configure the C extension"
    extension = extensions[0]
    assert all("wrong_path" not in str(path) for path in (extension.include_dirs or [])), \
        "the broken include path is still configured"
    libraries = list(extension.libraries or [])
    flags = list(extension.extra_compile_args or []) + list(extension.extra_link_args or [])
    assert "m" in libraries or "-lm" in flags, "setup.py is still missing the math-library flag"

    installed = subprocess.run(
        [sys.executable, "-c", AGGREGATION_CHECK, "installed", "unused"],
        cwd="/tmp", capture_output=True, text=True, timeout=120
    )
    assert installed.returncode == 0, \
        f"installed quant-db extension failed independent checks:\n{installed.stdout}\n{installed.stderr}"

    with tempfile.TemporaryDirectory() as build_dir:
        built = subprocess.run(
            [sys.executable, "setup.py", "build_ext", "--build-lib", build_dir, "--force"],
            cwd=PROJECT, capture_output=True, text=True, timeout=180
        )
        assert built.returncode == 0, f"fresh extension build failed:\n{built.stdout}\n{built.stderr}"
        candidates = []
        for suffix in importlib.machinery.EXTENSION_SUFFIXES:
            candidates.extend(glob.glob(os.path.join(build_dir, "quant_db", "aggregator*" + suffix)))
        assert candidates, "fresh build did not produce a quant_db aggregator extension"
        checked = subprocess.run(
            [sys.executable, "-c", AGGREGATION_CHECK, "file", candidates[0]],
            cwd="/tmp", capture_output=True, text=True, timeout=120
        )
        assert checked.returncode == 0, \
            f"extension rebuilt from submitted C source failed:\n{checked.stdout}\n{checked.stderr}"


def test_recovered_records_json():
    """Verify exact recovery of every valid record in the original WAL."""
    wal_file = "/app/data/transaction.wal"
    json_file = "/app/data/recovered_records.json"

    assert os.path.isfile(wal_file), f"WAL file {wal_file} is missing"
    assert os.path.isfile(json_file), f"Recovered JSON file {json_file} is missing"

    p1 = json.dumps({"id": 1, "val": 100}).encode()
    p2 = json.dumps({"id": 2, "val": 200}).encode()
    original_wal = (
        struct.pack(">II", 0xDEADBEEF, len(p1)) + p1
        + b"garbage data that breaks things"
        + struct.pack(">II", 0xDEADBEEF, len(p2)) + p2
    )

    with open(wal_file, "rb") as f:
        data = f.read()
    assert data == original_wal, "transaction.wal was modified instead of recovered"

    expected_records = []
    i = 0
    while i < len(data) - 8:
        if data[i:i + 4] == b"\xde\xad\xbe\xef":
            length = struct.unpack(">I", data[i + 4:i + 8])[0]
            if i + 8 + length <= len(data):
                payload = data[i + 8:i + 8 + length]
                try:
                    expected_records.append(json.loads(payload.decode("utf-8")))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    pass
            i += 1
        else:
            i += 1

    with open(json_file, "r") as f:
        try:
            recovered_records = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("recovered_records.json is not valid JSON")

    assert isinstance(recovered_records, list), "Recovered records should be a JSON list"
    assert len(recovered_records) > 0, "Recovered records list is empty"
    assert recovered_records == expected_records, \
        f"recovered records differ from valid WAL records: {recovered_records!r}"


def parse_sanitizer_output(sanitizer_script, corpus_dir):
    result = subprocess.run(
        [sys.executable, sanitizer_script, corpus_dir],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Sanitizer failed on {corpus_dir}:\n{result.stderr}"
    results = {}
    for line in result.stdout.strip().splitlines():
        if ":" in line:
            filename, status = line.split(":", 1)
            results[filename.strip()] = status.strip()
    return results


def test_sanitizer_adversarial_corpus():
    """Keep corpus checks and add a mixed, randomized structural test corpus."""
    sanitizer_script = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_script), f"Sanitizer script {sanitizer_script} is missing"

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(evil_dir), "Evil corpus directory missing"
    assert os.path.isdir(clean_dir), "Clean corpus directory missing"

    evil_results = parse_sanitizer_output(sanitizer_script, evil_dir)
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".dat")]
    bypassed_evil = [f for f in evil_files if evil_results.get(f) != "REJECT"]

    clean_results = parse_sanitizer_output(sanitizer_script, clean_dir)
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".dat")]
    modified_clean = [f for f in clean_files if clean_results.get(f) != "ACCEPT"]

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {bypassed_evil[:5]}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {modified_clean[:5]}")
    if errors:
        pytest.fail(" | ".join(errors))

    token = uuid.uuid4().hex
    cases = {
        f"normal_{token}.dat": ({"type": "telemetry", "data": 731, "tag": token}, "ACCEPT"),
        f"nested_clean_{token}.dat": ({"type": "telemetry", "data": {"class": "sensor", "note": "__class__"}}, "ACCEPT"),
        f"attack_{token}.dat": ({"type": "telemetry", "data": {"__class__": "random.module.call"}}, "REJECT"),
        f"deep_attack_{token}.dat": ({"type": "telemetry", "data": {"items": [{"__class__": "other.module.exec"}]}}, "REJECT"),
    }
    with tempfile.TemporaryDirectory(prefix="payload-check-") as mixed_dir:
        for filename, (payload, _) in cases.items():
            with open(os.path.join(mixed_dir, filename), "w") as f:
                json.dump(payload, f)
        results = parse_sanitizer_output(sanitizer_script, mixed_dir)
        assert set(results) == set(cases), "sanitizer did not emit exactly one result for every .dat file"
        for filename, (_, expected) in cases.items():
            assert results[filename] == expected, \
                f"{filename} was {results[filename]!r}, expected {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
