#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import os
import struct
import subprocess
import sys
import tempfile
import time
import pytest

EVIL_CORPUS_PATH = "/app/corpora/evil/"
CLEAN_CORPUS_PATH = "/app/corpora/clean/"
SANITIZER_SCRIPT = "/home/user/sanitizer.py"
EXT_DIR = "/home/user/py3_ext"
SETUP_PY = os.path.join(EXT_DIR, "setup.py")


def run_sanitizer(data, input_name="sample.bin", precreate_output=False):
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, input_name)
        output_path = os.path.join(tmpdir, "result.bin")
        with open(input_path, "wb") as f:
            f.write(data)
        if precreate_output:
            with open(output_path, "wb") as f:
                f.write(b"stale")
        result = subprocess.run(
            ["python3", SANITIZER_SCRIPT, input_path, output_path],
            capture_output=True,
            timeout=10,
        )
        output = None
        if os.path.exists(output_path):
            with open(output_path, "rb") as f:
                output = f.read()
        return result, output


def valid(records):
    return b"TLV1" + b"".join(struct.pack("<BH", typ, len(payload)) + payload for typ, payload in records)


def invalid_cases():
    # Derived from the format and the documented unsafe branches, with varying data
    # and neutral temporary path names (not the visible corpus paths).
    return [
        b"",
        b"TLV1",
        b"TLV1\x01",
        b"TLV1\x01\x01",
        b"TLV1" + struct.pack("<BH", 1, 7) + b"abc",
        b"TLV1" + struct.pack("<BH", 1, 300) + os.urandom(300),
        b"TLV1" + struct.pack("<BH", 0xFF, 10) + os.urandom(10),
        b"TLV1" + struct.pack("<BH", 1, 0),
        valid([(2, b"ok")]) + b"\x03",
    ]


def test_required_artifacts_and_native_import():
    assert os.path.isfile(SANITIZER_SCRIPT), f"Missing sanitizer script at {SANITIZER_SCRIPT}"
    assert os.path.isfile(SETUP_PY), f"Missing setup.py at {SETUP_PY}"

    subprocess.run(
        [sys.executable, SETUP_PY, "build_ext", "--inplace"],
        cwd=EXT_DIR,
        check=True,
        capture_output=True,
        timeout=60,
    )
    code = r'''
import importlib.machinery, os, sys
sys.path.insert(0, "/home/user/py3_ext")
import fast_tlv
p = os.path.realpath(fast_tlv.__file__)
assert any(p.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), p
assert callable(fast_tlv.parse)
try:
    fast_tlv.parse(b"TLV1\x01\x00\x00")
except ValueError:
    pass
else:
    raise AssertionError("malformed input did not raise ValueError")
fast_tlv.parse(b"TLV1\x01\x03\x00abc")
'''
    subprocess.run([sys.executable, "-c", code], check=True, capture_output=True, timeout=10)


def test_sanitizer_really_loads_fast_tlv_extension():
    # Supplying an earlier fake module makes import/use observable. A wrapper that
    # does not import and call fast_tlv cannot produce the required marker.
    with tempfile.TemporaryDirectory() as d:
        marker = os.path.join(d, "called")
        with open(os.path.join(d, "fast_tlv.py"), "w") as f:
            f.write("import os\ndef parse(data):\n open(os.environ['TLV_MARKER'],'wb').write(data)\n raise ValueError('probe')\n")
        inp = os.path.join(d, "input.bin")
        out = os.path.join(d, "output.bin")
        payload = b"TLV1\x01\x03\x00xyz"
        open(inp, "wb").write(payload)
        env = os.environ.copy()
        env["PYTHONPATH"] = d + os.pathsep + EXT_DIR
        env["TLV_MARKER"] = marker
        result = subprocess.run([sys.executable, SANITIZER_SCRIPT, inp, out], env=env, capture_output=True, timeout=10)
        assert result.returncode == 1
        assert not os.path.exists(out)
        assert os.path.isfile(marker) and open(marker, "rb").read() == payload


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_PATH) if os.path.isfile(os.path.join(EVIL_CORPUS_PATH, f))]
    assert evil_files, "No files found in evil corpus."
    bypassed = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_CORPUS_PATH, filename)
            output_path = os.path.join(tmpdir, filename)
            result = subprocess.run([sys.executable, SANITIZER_SCRIPT, input_path, output_path], capture_output=True, timeout=10)
            if result.returncode != 1 or os.path.exists(output_path):
                bypassed.append(filename)
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_PATH) if os.path.isfile(os.path.join(CLEAN_CORPUS_PATH, f))]
    assert clean_files, "No files found in clean corpus."
    modified = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_PATH, filename)
            output_path = os.path.join(tmpdir, filename)
            result = subprocess.run([sys.executable, SANITIZER_SCRIPT, input_path, output_path], capture_output=True, timeout=10)
            if result.returncode != 0 or not os.path.exists(output_path):
                modified.append(filename)
                continue
            if open(input_path, "rb").read() != open(output_path, "rb").read():
                modified.append(filename)
    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified. Offending files: {', '.join(modified)}")


def test_generated_inputs_and_output_safety():
    good = [
        valid([(1, b"A")]),
        valid([(2, os.urandom(17)), (3, b"B" * 255), (4, b"tail")]),
        valid([(i % 200 + 1, bytes([i]) * (i % 31 + 1)) for i in range(40)]),
    ]
    for i, data in enumerate(good):
        result, output = run_sanitizer(data, f"neutral_good_{i}.dat")
        assert result.returncode == 0
        assert output == data
    for i, data in enumerate(invalid_cases()):
        result, output = run_sanitizer(data, f"neutral_bad_{i}.dat", precreate_output=True)
        assert result.returncode == 1
        assert output is None, "rejected input left an output file"


def test_performance_benchmark():
    env = os.environ.copy()
    env["PYTHONPATH"] = EXT_DIR + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run(
        [sys.executable, "/home/user/benchmark.py"],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Benchmark passed!" in result.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
