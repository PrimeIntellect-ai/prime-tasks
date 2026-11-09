#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import scipy.io.wavfile as wav

HOME = "/home/user"
WAV_PATH = "/app/telemetry.wav"
PARSED_PATH = os.path.join(HOME, "parsed_data.txt")


def generate_recording(seed):
    rng = np.random.RandomState(seed)
    sample_rate = 16000
    pulse_len = 1600
    silence_len = 800
    t = np.linspace(0, 0.1, pulse_len, endpoint=False)
    audio = []
    peaks = []
    for _ in range(50):
        amp = rng.uniform(0.1, 1.0)
        pulse = amp * np.sin(2 * np.pi * 1000 * t)
        pulse += rng.normal(0, 0.01, pulse_len)
        pulse = np.asarray(pulse, dtype=np.float32)
        peaks.append(float(np.max(np.abs(pulse))))
        audio.extend(pulse)
        audio.extend(np.zeros(silence_len))
    return sample_rate, np.asarray(audio, dtype=np.float32), np.asarray(peaks)


def run(cmd, timeout=30, env=None):
    return subprocess.run(
        cmd, cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=True, env=env
    )


def run_extractor(expected):
    if os.path.lexists(PARSED_PATH):
        os.unlink(PARSED_PATH)
    run(["python3", os.path.join(HOME, "extract.py")])
    assert os.path.isfile(PARSED_PATH), "extract.py did not create parsed_data.txt"
    with open(PARSED_PATH) as f:
        lines = f.read().splitlines()
    assert len(lines) == 50, f"Expected 50 extracted values, found {len(lines)}"
    try:
        values = np.asarray([float(line.strip()) for line in lines])
    except ValueError as exc:
        raise AssertionError("parsed_data.txt contains a non-numeric line") from exc
    assert np.all(np.isfinite(values)), "Extracted values must be finite"
    assert np.allclose(values, expected, rtol=1e-5, atol=1e-6), (
        "extract.py did not report the maximum absolute value of every pulse"
    )
    return values


def run_compute(executable):
    result = run([executable])
    tokens = result.stdout.split()
    assert len(tokens) == 1, f"Compute program must print one float, got: {result.stdout!r}"
    value = float(tokens[0])
    assert np.isfinite(value), "Compute program returned a non-finite value"
    return value


def test_complete_pipeline():
    extract_path = os.path.join(HOME, "extract.py")
    source_path = os.path.join(HOME, "compute.c")
    binary_path = os.path.join(HOME, "compute")
    result_path = os.path.join(HOME, "final_result.txt")

    assert os.path.isfile(extract_path), "extract.py was not found"
    assert os.path.isfile(source_path), "compute.c was not found"
    assert os.path.isfile(binary_path), "Compiled /home/user/compute was not found"
    assert os.access(binary_path, os.X_OK), "/home/user/compute is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/compute is not a compiled ELF program"

    canonical_rate, canonical_audio, canonical_peaks = generate_recording(42)
    wav.write(WAV_PATH, canonical_rate, canonical_audio)
    expected_energy = float(np.sum(canonical_peaks ** 2))

    # Preserve the original result assertion, using the amplitudes actually encoded
    # in the recording rather than an incorrectly reconstructed RNG sequence.
    assert os.path.isfile(result_path), f"Result file {result_path} was not found."
    with open(result_path) as f:
        content = f.read().strip()
    try:
        final_value = float(content)
    except ValueError as exc:
        raise AssertionError(f"Could not parse a numerical float from {result_path}: {content!r}") from exc
    assert np.isfinite(final_value), "final_result.txt must contain a finite float"
    relative_error = abs(expected_energy - final_value) / expected_energy
    assert relative_error <= 0.05, (
        f"Relative error {relative_error:.4f} exceeds 0.05; "
        f"expected approximately {expected_energy:.6f}, got {final_value:.6f}"
    )

    # Execute the extractor on the customer recording and on a second recording
    # whose answers are derived by the verifier.
    canonical_values = run_extractor(canonical_peaks)
    challenge_rate, challenge_audio, challenge_peaks = generate_recording(9137)
    wav.write(WAV_PATH, challenge_rate, challenge_audio)
    run_extractor(challenge_peaks)

    # Compile the submitted source with memory-safety instrumentation, then test
    # both it and the requested compiled artifact on a full 50-value dataset.
    checked_binary = "/tmp/compute_from_source"
    run([
        "gcc", "-std=c11", "-O0", "-g", "-fsanitize=address,undefined",
        "-fno-omit-frame-pointer", source_path, "-o", checked_binary
    ])
    test_text = [format(float(x), ".9g") for x in np.linspace(-1.25, 2.75, 50)]
    parsed_test = [np.float32(float(x)) for x in test_text]
    expected_test = np.float32(0.0)
    for value in parsed_test:
        expected_test = np.float32(expected_test + np.float32(value * value))
    with open(PARSED_PATH, "w") as f:
        f.write("\n".join(test_text) + "\n")

    sanitizer_env = os.environ.copy()
    sanitizer_env["ASAN_OPTIONS"] = "detect_leaks=0"
    checked = run_compute_with_env(checked_binary, sanitizer_env)
    installed = run_compute(binary_path)
    assert abs(checked - float(expected_test)) <= 1e-4, "compute.c calculates the wrong sum"
    assert abs(installed - float(expected_test)) <= 1e-4, "/home/user/compute calculates the wrong sum"

    # Restore and execute the complete canonical pipeline, then require the saved
    # result to agree with the compiled program's output.
    wav.write(WAV_PATH, canonical_rate, canonical_audio)
    restored_values = run_extractor(canonical_peaks)
    assert np.allclose(restored_values, canonical_values, rtol=1e-7, atol=1e-7)
    pipeline_value = run_compute(binary_path)
    assert abs(pipeline_value - expected_energy) / expected_energy <= 1e-4
    assert abs(final_value - pipeline_value) / expected_energy <= 1e-4, (
        "final_result.txt does not match the output of the repaired pipeline"
    )


def run_compute_with_env(executable, env):
    result = run([executable], env=env)
    tokens = result.stdout.split()
    assert len(tokens) == 1, f"Compute program must print one float, got: {result.stdout!r}"
    value = float(tokens[0])
    assert np.isfinite(value), "Compute program returned a non-finite value"
    return value
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
