#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import random
import struct
import subprocess
import tempfile
import uuid
import wave

import pytest

EXPECTED_KEY = "7f8b9c2a1d3e4f5a6b7c8d9e0f1a2b3c"


def test_api_key_extracted():
    api_key_path = "/home/user/api_key.txt"
    assert os.path.isfile(api_key_path), f"Missing API key file at {api_key_path}"
    with open(api_key_path, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_KEY, f"Incorrect API key extracted. Found: {content}"


def test_detect_anomaly_script_exists():
    script_path = "/home/user/detect_anomaly.py"
    assert os.path.isfile(script_path), f"Missing anomaly detection script at {script_path}"


def test_audio_processor_deadlock_repaired():
    processor = "/app/audio_processor.py"
    assert os.path.isfile(processor), f"Missing pipeline module at {processor}"
    code = "import sys; sys.path.insert(0, '/app'); import audio_processor; audio_processor.process_batch(); print('DONE')"
    try:
        result = subprocess.run(
            ["python3", "-c", code], capture_output=True, text=True, timeout=3
        )
    except subprocess.TimeoutExpired:
        pytest.fail("audio_processor.process_batch() still deadlocks")
    assert result.returncode == 0, result.stderr
    assert "DONE" in result.stdout


def test_math_filter_converges_on_problematic_inputs():
    path = "/app/math_filter.py"
    assert os.path.isfile(path), f"Missing mathematical filter at {path}"
    spec = importlib.util.spec_from_file_location("repaired_math_filter", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    inputs = [-10.0, -2.0, -1.0, -0.9, 0.0, 0.2, 0.5,
              math.sqrt(1.0 / 3.0), 0.6, 0.9, 1.0, 2.0, 10.0]
    for value in inputs:
        try:
            output = module.denoise_signal(value)
        except Exception as exc:
            pytest.fail(f"denoise_signal({value!r}) crashed: {exc!r}")
        assert isinstance(output, (int, float)), f"Non-numeric output for {value!r}: {output!r}"
        assert math.isfinite(float(output)), f"Non-finite output for {value!r}: {output!r}"
        assert abs(float(module.f(output))) < 1e-6, (
            f"denoise_signal({value!r}) did not converge to a root: {output!r}"
        )


def test_adversarial_corpus():
    script_path = "/home/user/detect_anomaly.py"
    clean_dir = "/app/clean"
    evil_dir = "/app/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus dir: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus dir: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert clean_files, "Clean corpus is empty."
    assert evil_files, "Evil corpus is empty."

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        res = subprocess.run(["python3", script_path, cf], capture_output=True, text=True)
        if res.returncode != 0 or "CLEAN" not in res.stdout:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        res = subprocess.run(["python3", script_path, ef], capture_output=True, text=True)
        if res.returncode != 1 or "EVIL" not in res.stdout:
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def _make_wav(path, sample):
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        wav.writeframes(struct.pack("<h", sample))


def test_detection_uses_audio_decryption_and_filtering_without_path_labels():
    script_path = "/home/user/detect_anomaly.py"

    with tempfile.TemporaryDirectory(prefix="audio_inputs_") as audio_dir, \
         tempfile.TemporaryDirectory(prefix="instrument_") as instrument_dir:
        sitecustomize = os.path.join(instrument_dir, "sitecustomize.py")
        with open(sitecustomize, "w") as f:
            f.write(r'''
import os
import audio_processor
import math_filter

_marker = os.environ.get("DETECTION_MARKER")
_expected = os.environ.get("EXPECTED_API_KEY")
_decrypted = False
_original_decrypt = audio_processor.decrypt
_original_filter = math_filter.denoise_signal

def _record(line):
    if _marker:
        with open(_marker, "a") as out:
            out.write(line + "\n")

def checked_decrypt(file_path, key):
    global _decrypted
    _record("decrypt:" + str(key))
    if str(key) != _expected:
        raise RuntimeError("detector supplied the wrong API key")
    result = _original_decrypt(file_path, key)
    _decrypted = True
    return result

def checked_filter(value):
    if not _decrypted:
        raise RuntimeError("filter was called before decryption")
    _record("filter")
    return _original_filter(value)

audio_processor.decrypt = checked_decrypt
math_filter.denoise_signal = checked_filter
''')

        cases = []
        for sample, expected_text, expected_code in [
            (0, "CLEAN", 0), (1000, "EVIL", 1),
            (0, "CLEAN", 0), (1000, "EVIL", 1),
        ]:
            path = os.path.join(audio_dir, uuid.uuid4().hex + ".wav")
            _make_wav(path, sample)
            cases.append((path, expected_text, expected_code))
        random.SystemRandom().shuffle(cases)

        for path, expected_text, expected_code in cases:
            marker = os.path.join(audio_dir, uuid.uuid4().hex + ".log")
            env = os.environ.copy()
            env["PYTHONPATH"] = instrument_dir + os.pathsep + "/app"
            env["DETECTION_MARKER"] = marker
            env["EXPECTED_API_KEY"] = EXPECTED_KEY
            result = subprocess.run(
                ["python3", script_path, path], capture_output=True, text=True,
                env=env, timeout=10
            )
            assert result.returncode == expected_code, (
                f"Wrong exit code for neutral-path audio: {result.stdout!r} {result.stderr!r}"
            )
            assert result.stdout.strip() == expected_text, (
                f"Wrong classification for neutral-path audio: {result.stdout!r}"
            )
            assert os.path.isfile(marker), "Detector did not call the instrumented pipeline"
            with open(marker) as f:
                events = [line.strip() for line in f if line.strip()]
            decrypt_event = "decrypt:" + EXPECTED_KEY
            assert decrypt_event in events, "Detector did not decrypt with the extracted API key"
            assert "filter" in events, "Detector did not pass the audio through denoise_signal()"
            assert events.index(decrypt_event) < events.index("filter"), (
                "Detector must decrypt before applying the mathematical filter"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
