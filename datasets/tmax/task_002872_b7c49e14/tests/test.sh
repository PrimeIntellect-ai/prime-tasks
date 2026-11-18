#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import struct
import subprocess
import time
import pytest

TARGET_EXE = "/home/user/dsp_processor_fixed"
SUSPICIOUS_WAV = "/app/suspicious_audio.wav"
HEADER = struct.Struct("<4sI4s4sIHHIIHH4sI")


def read_float_wav(path):
    with open(path, "rb") as f:
        raw = f.read()

    assert len(raw) >= HEADER.size, f"{path} is too short to contain a WAV header."
    fields = HEADER.unpack_from(raw)
    (riff, wav_size, wave, fmt, fmt_size, audio_format, channels,
     sample_rate, byte_rate, alignment, bit_depth, data_tag, data_bytes) = fields

    assert riff == b"RIFF", "Output has no RIFF signature."
    assert wave == b"WAVE", "Output has no WAVE signature."
    assert fmt == b"fmt ", "Output has no fmt chunk."
    assert data_tag == b"data", "Output has no data chunk."
    assert fmt_size == 16, "Unexpected fmt chunk size."
    assert audio_format == 3, "Output is not IEEE 32-bit float WAV."
    assert channels == 1, "Output is not mono."
    assert bit_depth == 32 and alignment == 4, "Output is not 32-bit float audio."
    assert byte_rate == sample_rate * alignment, "Invalid WAV byte rate."
    assert data_bytes % 4 == 0, "WAV data size is not a whole number of floats."
    assert wav_size == 36 + data_bytes, "Invalid RIFF size."
    assert len(raw) == HEADER.size + data_bytes, "File length does not match WAV data size."

    samples = struct.unpack_from(f"<{data_bytes // 4}f", raw, HEADER.size)
    return raw[:HEADER.size], fields, samples


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def reference_filter(samples):
    alpha = f32(0.999)
    feed = f32(f32(1.0) - alpha)
    y = f32(0.0)
    result = []
    for x in samples:
        y = f32(f32(f32(x) * feed) + f32(y * alpha))
        result.append(y)
    return result


def run_processor(input_wav, output_wav, timeout=10):
    if os.path.exists(output_wav):
        os.remove(output_wav)
    try:
        return subprocess.run(
            [TARGET_EXE, input_wav, output_wav],
            check=True,
            timeout=timeout,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution timed out. The denormal issue is likely not fixed.")
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Executable crashed with return code {e.returncode}. Stderr: {e.stderr}"
        )


def write_probe(path, samples, sample_rate=44100):
    data = struct.pack(f"<{len(samples)}f", *samples)
    header = HEADER.pack(
        b"RIFF", 36 + len(data), b"WAVE", b"fmt ", 16, 3, 1,
        sample_rate, sample_rate * 4, 4, 32, b"data", len(data)
    )
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def test_executable_exists_and_is_executable():
    assert os.path.exists(TARGET_EXE), f"Executable {TARGET_EXE} does not exist."
    assert os.path.isfile(TARGET_EXE), f"Path {TARGET_EXE} is not a file."
    assert os.access(TARGET_EXE, os.X_OK), f"File {TARGET_EXE} is not executable."


def test_execution_time_and_output():
    input_wav = SUSPICIOUS_WAV
    output_wav = "/tmp/eval_out.wav"

    assert os.path.exists(input_wav), f"Input audio {input_wav} is missing."

    start_time = time.time()
    run_processor(input_wav, output_wav)
    runtime = time.time() - start_time

    assert os.path.exists(output_wav), f"Output file {output_wav} was not created."
    assert os.path.getsize(output_wav) > 0, f"Output file {output_wav} is empty."

    threshold = 0.2
    assert runtime <= threshold, (
        f"Execution time {runtime:.4f}s exceeded the threshold of {threshold}s. "
        "The denormal issue is likely not fixed."
    )

    in_header, in_fields, input_samples = read_float_wav(input_wav)
    out_header, out_fields, output_samples = read_float_wav(output_wav)
    assert out_header == in_header, "Output WAV header does not preserve the input format."
    assert len(output_samples) == len(input_samples), "Output sample count differs from input."
    assert all(math.isfinite(x) for x in output_samples), "Output contains NaN or infinity."

    check_count = min(12000, len(input_samples))
    expected = reference_filter(input_samples[:check_count])
    for i, (actual, wanted) in enumerate(zip(output_samples[:check_count], expected)):
        assert abs(actual - wanted) <= 2e-6 + 2e-4 * abs(wanted), (
            f"Incorrect filtered sample {i}: got {actual}, expected approximately {wanted}."
        )

    if len(output_samples) >= 1000:
        assert max(abs(x) for x in output_samples[-1000:]) <= 1e-8, (
            "The decaying impulse has an unexpectedly large tail."
        )


def test_filter_on_independent_audio():
    input_wav = "/tmp/verifier_probe.wav"
    output_wav = "/tmp/verifier_probe_out.wav"
    rng = secrets.SystemRandom()
    samples = [1.0, -0.75, 0.5, 0.0]
    samples.extend(rng.uniform(-0.9, 0.9) for _ in range(16380))
    write_probe(input_wav, samples)

    run_processor(input_wav, output_wav)
    assert os.path.exists(output_wav), "No output was produced for the independent test WAV."
    assert os.path.getsize(output_wav) > 0, "Independent test output is empty."

    input_header, _, parsed_input = read_float_wav(input_wav)
    output_header, _, actual = read_float_wav(output_wav)
    assert output_header == input_header, "Independent output WAV header was altered."
    assert len(actual) == len(parsed_input), "Independent output has the wrong sample count."
    assert all(math.isfinite(x) for x in actual), "Independent output contains NaN or infinity."

    expected = reference_filter(parsed_input)
    assert max(abs(x) for x in expected) > 1e-3
    for i, (got, wanted) in enumerate(zip(actual, expected)):
        assert abs(got - wanted) <= 2e-5 + 2e-4 * abs(wanted), (
            f"Filter result is incorrect at independent sample {i}: "
            f"got {got}, expected approximately {wanted}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
