#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import wave
import shutil
import subprocess
import tempfile

import numpy as np
import pytest
from scipy.io import wavfile

THRESHOLD = 150
MIN_SILENCE_MS = 500


def expected_trim(data, sample_rate):
    samples = np.asarray(data, dtype=np.int16)
    quiet = np.abs(samples.astype(np.int64)) < THRESHOLD
    keep = np.ones(len(samples), dtype=bool)
    start = 0
    while start < len(samples):
        if not quiet[start]:
            start += 1
            continue
        end = start + 1
        while end < len(samples) and quiet[end]:
            end += 1
        if (end - start) * 1000 > MIN_SILENCE_MS * sample_rate:
            keep[start:end] = False
        start = end
    return samples[keep]


def assert_wav_matches(path, expected_rate, expected_samples):
    assert os.path.isfile(path), f"Missing WAV output: {path}"
    try:
        sample_rate, data = wavfile.read(path)
    except Exception as exc:
        pytest.fail(f"Could not read {path} as a valid WAV file: {exc}")
    assert sample_rate == expected_rate, "The sample rate was not preserved"
    assert data.dtype == np.int16, "Output must remain 16-bit PCM"
    assert data.ndim == 1, "Output must remain mono"
    assert len(data) > 0, "Optimized WAV file contains no audio data"
    assert np.array_equal(data, expected_samples), (
        "Output does not exactly preserve all non-trimmed samples or trims "
        "silence using the wrong threshold/duration"
    )


def test_final_storage_archive():
    archive_path = "/home/user/final_storage.tar.gz"
    assert os.path.isfile(archive_path), f"Missing final archive: {archive_path}"

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any(n.endswith("optimized.wav") for n in names), "optimized.wav not found in final_storage.tar.gz"
        assert any(n.endswith("settings.ini") for n in names), "settings.ini not found in final_storage.tar.gz"


def test_optimized_wav_size_validity_and_audio_content():
    optimized_path = "/home/user/optimized.wav"
    original_path = "/app/voicemail.wav"

    assert os.path.isfile(optimized_path), f"Missing optimized file: {optimized_path}"

    original_size = os.path.getsize(original_path)
    new_size = os.path.getsize(optimized_path)
    size_ratio = new_size / original_size
    assert size_ratio <= 0.70, f"Not enough space saved. Size ratio: {size_ratio:.3f} (must be <= 0.70)"

    try:
        sample_rate, original = wavfile.read(original_path)
    except Exception as exc:
        pytest.fail(f"Could not read original WAV: {exc}")
    assert original.dtype == np.int16 and original.ndim == 1
    expected = expected_trim(original, sample_rate)
    assert_wav_matches(optimized_path, sample_rate, expected)


def test_cpp_trimmer_compiles_and_processes_derived_input():
    source = "/home/user/silence_trimmer.cpp"
    assert os.path.isfile(source), f"Missing C++ source: {source}"

    work = tempfile.mkdtemp(prefix="trimmer_test_")
    binary = os.path.join(work, "silence_trimmer")
    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compiled.returncode == 0, f"silence_trimmer.cpp did not compile:\n{compiled.stderr}"

    rate = 8000
    rng = np.random.default_rng(918273)
    loud1 = rng.integers(900, 12000, 2371, dtype=np.int16)
    short_quiet = rng.integers(-149, 150, 1733, dtype=np.int16)
    loud2 = -rng.integers(900, 12000, 2819, dtype=np.int16)
    long_quiet = rng.integers(-149, 150, 4617, dtype=np.int16)
    loud3 = rng.integers(900, 12000, 1907, dtype=np.int16)
    exact_loud = np.array([150, -150, 151, -151], dtype=np.int16)
    samples = np.concatenate([loud1, short_quiet, loud2, long_quiet, exact_loud, loud3])
    expected = expected_trim(samples, rate)

    custom_input = os.path.join(work, "voicemail.wav")
    wavfile.write(custom_input, rate, samples)
    shutil.copyfile(custom_input, os.path.join(work, "input.wav"))
    with open(os.path.join(work, "settings.ini"), "w") as f:
        f.write("[Audio]\namplitude_threshold=150\nmin_silence_duration_ms=500\n")

    app_input = "/app/voicemail.wav"
    home_output = "/home/user/optimized.wav"
    app_backup = open(app_input, "rb").read()
    home_backup = open(home_output, "rb").read() if os.path.exists(home_output) else None

    output_paths = [
        os.path.join(work, "result.wav"),
        os.path.join(work, "optimized.wav"),
        home_output,
    ]
    invocations = [
        [binary, custom_input, output_paths[0], "150", "500"],
        [binary, custom_input, output_paths[0]],
        [binary, "150", "500", custom_input, output_paths[0]],
        [binary, custom_input, "150", "500", output_paths[0]],
        [binary, custom_input, output_paths[0], os.path.join(work, "settings.ini")],
        [binary],
    ]

    matched = False
    errors = []
    try:
        shutil.copyfile(custom_input, app_input)
        for command in invocations:
            for candidate in output_paths:
                if os.path.exists(candidate):
                    os.remove(candidate)
            try:
                result = subprocess.run(
                    command,
                    cwd=work,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
                errors.append(f"{command[1:]}: exit {result.returncode}; {result.stderr[-300:]}")
            except (subprocess.TimeoutExpired, OSError) as exc:
                errors.append(f"{command[1:]}: {exc}")
                continue

            for candidate in output_paths:
                if not os.path.isfile(candidate):
                    continue
                try:
                    candidate_rate, candidate_data = wavfile.read(candidate)
                    if (candidate_rate == rate and candidate_data.dtype == np.int16 and
                            candidate_data.ndim == 1 and np.array_equal(candidate_data, expected)):
                        matched = True
                        break
                except Exception:
                    pass
            if matched:
                break
    finally:
        with open(app_input, "wb") as f:
            f.write(app_backup)
        if home_backup is None:
            if os.path.exists(home_output):
                os.remove(home_output)
        else:
            with open(home_output, "wb") as f:
                f.write(home_backup)
        shutil.rmtree(work, ignore_errors=True)

    assert matched, (
        "The compiled C++ trimmer did not produce the correctly trimmed WAV on a "
        "derived test recording. Attempts:\n" + "\n".join(errors)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
