#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import importlib
import importlib.machinery
import importlib.util
import os
import runpy
import secrets
import struct
import subprocess
import sys
import tempfile
import types

import pytest

RECOVER_PATH = "/home/user/recover.py"
WAL_PATH = "/app/suspicious.wal"
LOG_PATH = "/home/user/extracted.log"


def _write_wal(path, payloads):
    records = []
    for i, payload in enumerate(payloads):
        encoded = payload.encode("utf-8")
        records.append(struct.pack("<i", len(encoded)) + encoded)
        if i % 6 == 0:
            # Match the corruption used by the supplied WAL: a negative length
            # followed by abs(length) bytes which must be skipped safely.
            records.append(struct.pack("<i", -16) + os.urandom(16))
    with gzip.open(path, "wb") as f:
        f.write(b"".join(records))


def _read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def _run_recovery():
    result = subprocess.run(
        [sys.executable, RECOVER_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"recover.py failed with exit status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Expected output file not found at {LOG_PATH}."


def test_required_artifacts_and_walparse_behavior():
    assert os.path.isfile(RECOVER_PATH), f"Expected recovery script not found at {RECOVER_PATH}."
    assert os.path.isfile("/app/libwalparse/wal_parse.c"), "Vendored C source is missing."
    assert os.path.isfile("/app/libwalparse/setup.py"), "Vendored build script is missing."

    spec = importlib.util.find_spec("walparse")
    assert spec is not None and spec.origin, "The walparse extension is not installed."
    assert any(spec.origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"walparse must be a compiled Python extension, but resolved to {spec.origin!r}."
    )

    nonce = secrets.token_hex(12)
    payloads = [f"DYNAMIC_{nonce}_{i}_{secrets.token_hex(5)}" for i in range(40)]

    with tempfile.TemporaryDirectory() as td:
        test_wal = os.path.join(td, "challenge.wal")
        _write_wal(test_wal, payloads)

        walparse = importlib.import_module("walparse")
        parsed = walparse.parse(test_wal)
        normalized = set()
        for value in parsed:
            if isinstance(value, bytes):
                try:
                    normalized.add(value.decode("utf-8"))
                except UnicodeDecodeError:
                    continue
            elif isinstance(value, str):
                normalized.add(value)

        expected = set(payloads)
        direct_recall = len(expected.intersection(normalized)) / len(expected)
        assert direct_recall >= 0.95, (
            f"walparse.parse did not recover the generated WAL: recall={direct_recall:.2f}."
        )

        # Execute recover.py with a controlled walparse module. Its output must
        # come from walparse.parse rather than an independent/hard-coded parser.
        sentinel = f"WALPARSE_SPY_{secrets.token_hex(16)}"
        calls = []
        fake_module = types.ModuleType("walparse")

        def fake_parse(filename):
            calls.append(filename)
            return [sentinel.encode("utf-8")]

        fake_module.parse = fake_parse
        old_module = sys.modules.get("walparse")
        sys.modules["walparse"] = fake_module
        try:
            runpy.run_path(RECOVER_PATH, run_name="__main__")
        finally:
            if old_module is None:
                sys.modules.pop("walparse", None)
            else:
                sys.modules["walparse"] = old_module

        assert calls, "recover.py did not call walparse.parse."
        assert _read_lines(LOG_PATH) == [sentinel], (
            "recover.py did not write the payload returned by walparse.parse."
        )

        # Replace the fixed WAL with an unpredictable one and execute the actual
        # script and installed extension together. Restore the supplied WAL after.
        with open(WAL_PATH, "rb") as f:
            original_wal = f.read()
        try:
            with open(test_wal, "rb") as src, open(WAL_PATH, "wb") as dst:
                dst.write(src.read())
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)
            _run_recovery()
            extracted = set(_read_lines(LOG_PATH))
            recall = len(expected.intersection(extracted)) / len(expected)
            assert recall >= 0.95, (
                f"recover.py failed on the generated WAL: recall={recall:.2f}."
            )
            assert extracted.issubset(expected), "Generated-WAL output contains non-payload data."
        finally:
            with open(WAL_PATH, "wb") as f:
                f.write(original_wal)

    # Re-run against the supplied WAL so the original output assertions below
    # continue to evaluate the requested final artifact.
    _run_recovery()


def test_extracted_log_recall():
    log_path = "/home/user/extracted.log"

    assert os.path.exists(log_path), f"Expected output file not found at {log_path}."
    assert os.path.isfile(log_path), f"Path {log_path} exists but is not a file."

    expected = set([f"SECRET_PAYLOAD_{i}" for i in range(100)])

    try:
        with open(log_path, "r") as f:
            extracted = set([line.strip() for line in f if line.strip()])
    except Exception as e:
        pytest.fail(f"Failed to read {log_path}: {e}")

    correct = len(expected.intersection(extracted))
    recall = correct / len(expected)

    threshold = 0.95
    assert recall >= threshold, (
        f"Recall metric failed. Expected recall >= {threshold}, but got {recall:.2f}. "
        f"Correctly extracted {correct} out of {len(expected)} expected payloads."
    )


def test_extracted_log_contains_no_garbage():
    log_path = "/home/user/extracted.log"
    if not os.path.exists(log_path):
        pytest.skip("Log file not found, skipping garbage check.")

    expected = set([f"SECRET_PAYLOAD_{i}" for i in range(100)])

    with open(log_path, "r") as f:
        extracted = set([line.strip() for line in f if line.strip()])

    # Preserve the original size assertion.
    assert len(extracted) <= 200, f"File contains too many lines ({len(extracted)}). Did the parser loop infinitely or extract garbage?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
