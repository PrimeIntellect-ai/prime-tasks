#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import shutil
import struct
import subprocess
import time
import wave

import pytest

ROOT = "/home/user/audioproc"
EXECUTABLE = ROOT + "/build/audioproc"
TELEMETRY = "/app/telemetry.wav"
OUTPUT = "/home/user/output.json"


def load_and_check_schema(path, expected_source):
    assert os.path.exists(path), f"Output JSON file not found at {path}."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse output JSON: {e}")

    assert "metadata" in data, "Key 'metadata' missing from JSON output."
    assert isinstance(data["metadata"], dict), "'metadata' should be an object."
    assert "source" in data["metadata"], "Key 'source' missing from 'metadata'."
    assert data["metadata"]["source"] == expected_source, (
        f"Expected metadata.source to be {expected_source!r}, got {data['metadata']['source']!r}"
    )

    assert "measurements" in data, "Key 'measurements' missing from JSON output."
    measurements = data["measurements"]
    assert isinstance(measurements, list), "'measurements' should be a list."
    assert len(measurements) > 0, "'measurements' list is empty."

    previous_index = -1
    for i, measurement in enumerate(measurements):
        assert isinstance(measurement, dict), f"Measurement at index {i} is not an object."
        assert "chunk_index" in measurement, f"'chunk_index' missing in measurement at index {i}."
        assert "rms_value" in measurement, f"'rms_value' missing in measurement at index {i}."
        chunk_index = measurement["chunk_index"]
        rms_value = measurement["rms_value"]
        assert isinstance(chunk_index, int) and not isinstance(chunk_index, bool), (
            f"'chunk_index' must be an integer, got {type(chunk_index)}."
        )
        assert isinstance(rms_value, (int, float)) and not isinstance(rms_value, bool), (
            f"'rms_value' must be a number, got {type(rms_value)}."
        )
        assert math.isfinite(float(rms_value)), f"Non-finite RMS value at measurement {i}."
        assert chunk_index > previous_index, (
            f"Measurements are not ordered by chunk_index. Found {chunk_index} after {previous_index}."
        )
        assert chunk_index == i, f"Expected contiguous chunk_index {i}, got {chunk_index}."
        previous_index = chunk_index
    return measurements


def run_program(executable, input_path, output_path, timeout=10, env=None):
    if os.path.exists(output_path):
        os.remove(output_path)
    proc = subprocess.run(
        [executable, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    assert proc.returncode == 0, (
        f"audioproc failed with exit code {proc.returncode}.\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    return load_and_check_schema(output_path, input_path)


def assert_rms_matches_contiguous_chunks(measurements, samples):
    # Chunk size was intentionally left as an implementation choice. Given the
    # reported count, accept any fixed-size contiguous partition that consumes
    # every input frame, and verify every RMS value for that partition.
    count = len(measurements)
    frames = len(samples)
    assert 2 <= count <= frames, f"Implausible chunk count {count} for {frames} frames."

    prefix = [0]
    total = 0
    for sample in samples:
        total += sample * sample
        prefix.append(total)

    minimum_size = (frames + count - 1) // count
    maximum_size = (frames - 1) // (count - 1)
    assert minimum_size <= maximum_size, "Reported chunk count cannot cover the input with fixed-size chunks."

    tolerance = 2e-4
    for chunk_size in range(minimum_size, maximum_size + 1):
        matched = True
        for i, measurement in enumerate(measurements):
            begin = i * chunk_size
            end = min(begin + chunk_size, frames)
            if begin >= end:
                matched = False
                break
            expected = math.sqrt((prefix[end] - prefix[begin]) / float(end - begin)) / 32768.0
            if abs(float(measurement["rms_value"]) - expected) > tolerance:
                matched = False
                break
        if matched:
            return
    pytest.fail("RMS values do not match any fixed-size contiguous chunking of the WAV samples.")


def make_random_wav(path):
    rng = random.SystemRandom()
    samples = [rng.randrange(-28000, 28001) for _ in range(65536)]
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        wav.writeframes(struct.pack("<{}h".format(len(samples)), *samples))
    return samples


def test_audioproc_complete_behavior():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did you build it?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.exists(TELEMETRY), f"Input audio file not found at {TELEMETRY}."

    # Preserve the original execution and 200 ms performance assertion.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    start = time.perf_counter()
    proc = subprocess.run([EXECUTABLE, TELEMETRY, OUTPUT], capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    assert proc.returncode == 0, (
        f"audioproc failed with exit code {proc.returncode}. stderr: {proc.stderr}"
    )
    assert elapsed <= 0.200, (
        f"Execution time {elapsed:.4f}s exceeds the 0.200s threshold. "
        "Concurrency might not be implemented correctly or is too slow."
    )
    telemetry_measurements = load_and_check_schema(OUTPUT, TELEMETRY)
    assert len(telemetry_measurements) >= 2, "The 600-second telemetry file must be split into multiple chunks."
    assert all(abs(float(m["rms_value"])) <= 1e-12 for m in telemetry_measurements), (
        "telemetry.wav contains silence, so every chunk RMS must be zero."
    )

    # Exercise the artifact on verifier-generated, unpredictable PCM data and
    # derive the expected RMS values directly from those samples.
    random_wav = "/tmp/verifier_audio.wav"
    random_output = "/tmp/verifier_audio.json"
    samples = make_random_wav(random_wav)
    measurements = run_program(EXECUTABLE, random_wav, random_output)
    assert_rms_matches_contiguous_chunks(measurements, samples)


def test_real_worker_pool_and_source_architecture():
    # Check the requested C++17 producer-consumer synchronization primitives in
    # uncommented source, then confirm the submitted executable actually creates
    # a pool (main thread plus at least two worker threads) while processing.
    source = ""
    for name in ("src/main.cpp", "src/processor.cpp"):
        path = os.path.join(ROOT, name)
        assert os.path.isfile(path), f"Required source file missing: {path}"
        source += open(path, "r", encoding="utf-8", errors="replace").read() + "\n"
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//.*", "", source)
    assert re.search(r"std\s*::\s*thread", source), "No std::thread-based worker implementation found."
    assert re.search(r"std\s*::\s*mutex", source), "No mutex-protected shared queue implementation found."
    assert re.search(r"std\s*::\s*condition_variable", source), (
        "No condition_variable-based producer-consumer coordination found."
    )

    monitored_output = "/tmp/thread_check.json"
    if os.path.exists(monitored_output):
        os.remove(monitored_output)
    proc = subprocess.Popen(
        [EXECUTABLE, TELEMETRY, monitored_output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    max_threads = 1
    deadline = time.monotonic() + 5
    while proc.poll() is None and time.monotonic() < deadline:
        try:
            max_threads = max(max_threads, len(os.listdir(f"/proc/{proc.pid}/task")))
        except FileNotFoundError:
            pass
        time.sleep(0.0005)
    if proc.poll() is None:
        proc.kill()
        pytest.fail("Monitored audioproc run timed out.")
    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, f"Monitored run failed. stdout: {stdout}\nstderr: {stderr}"
    assert max_threads >= 3, f"No active worker pool observed; maximum process thread count was {max_threads}."
    load_and_check_schema(monitored_output, TELEMETRY)


def test_sanitized_build_has_no_memory_or_lifetime_errors():
    build = "/tmp/audioproc_asan_build"
    shutil.rmtree(build, ignore_errors=True)
    configure = subprocess.run(
        [
            "cmake", "-S", ROOT, "-B", build,
            "-DCMAKE_BUILD_TYPE=Debug",
            "-DCMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer",
            "-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address,undefined",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert configure.returncode == 0, f"Sanitizer CMake configuration failed:\n{configure.stdout}\n{configure.stderr}"
    compiled = subprocess.run(
        ["cmake", "--build", build, "--parallel", "2"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compiled.returncode == 0, f"Sanitizer build failed:\n{compiled.stdout}\n{compiled.stderr}"

    asan_executable = os.path.join(build, "audioproc")
    assert os.path.isfile(asan_executable), "Sanitized audioproc target was not produced."
    wav_path = "/tmp/verifier_asan.wav"
    output_path = "/tmp/verifier_asan.json"
    samples = make_random_wav(wav_path)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    measurements = run_program(asan_executable, wav_path, output_path, timeout=20, env=env)
    assert_rms_matches_contiguous_chunks(measurements, samples)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
