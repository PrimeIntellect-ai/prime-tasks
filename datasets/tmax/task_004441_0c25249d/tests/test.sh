#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import struct
import subprocess
import tempfile
import wave

import pytest

AGENT_PATH = "/home/user/audio_analyzer_fixed"
SOURCE_PATH = "/home/user/audio_analyzer.c"
INPUT_PATH = "/home/user/test_input.bin"
OUTPUT_PATH = "/home/user/diagnostic_output.txt"
REGRESSION_PATH = "/home/user/run_regression.sh"

OUTPUT_RE = re.compile(
    r"^RMS: (-?\d+\.\d{6})\nVariance: (-?\d+\.\d{6})\n?$"
)


def expected_metrics(samples):
    assert samples
    count = len(samples)
    mean = math.fsum(samples) / count
    rms = math.sqrt(math.fsum(x * x for x in samples) / count)
    variance = math.fsum((x - mean) ** 2 for x in samples) / count
    return rms, variance


def make_input(samples, unknown_length=True, trailing=()):
    length = 0xFFFFFFFF if unknown_length else len(samples)
    header = b"DIAG" + struct.pack("<I", length) + (b"\x00" * 24)
    body = b"".join(struct.pack("<h", x) for x in list(samples) + list(trailing))
    return header + body


def run_analyzer(executable, input_data, timeout=10):
    with tempfile.NamedTemporaryFile() as input_file:
        input_file.write(input_data)
        input_file.flush()
        proc = subprocess.run(
            [executable, input_file.name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )

    assert proc.returncode == 0, (
        f"Analyzer exited with {proc.returncode}; stderr={proc.stderr!r}"
    )
    text = proc.stdout.decode("utf-8", errors="strict")
    match = OUTPUT_RE.fullmatch(text)
    assert match, f"Output must be exactly two lines with six decimal places: {text!r}"
    return float(match.group(1)), float(match.group(2)), proc.stdout


def assert_correct(executable, input_data, samples):
    actual_rms, actual_variance, _ = run_analyzer(executable, input_data)
    expected_rms, expected_variance = expected_metrics(samples)
    assert math.isfinite(actual_rms)
    assert math.isfinite(actual_variance)
    assert actual_rms == pytest.approx(expected_rms, abs=0.0001)
    assert actual_variance == pytest.approx(expected_variance, abs=0.02)


def test_student_files_exist():
    assert os.path.isfile(AGENT_PATH), f"Missing compiled executable: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Executable is not executable: {AGENT_PATH}"
    assert os.path.isfile(INPUT_PATH), "Missing /home/user/test_input.bin"
    assert os.path.isfile(OUTPUT_PATH), "Missing /home/user/diagnostic_output.txt"
    assert os.path.isfile(REGRESSION_PATH), "Missing /home/user/run_regression.sh"


def test_unknown_length_and_numerical_stability():
    # This has a massive DC offset and a true population variance of 0.25.
    # The original single-precision E[x^2]-E[x]^2 implementation cannot
    # calculate it reliably.
    samples = [30000, 30001] * 20000
    assert_correct(AGENT_PATH, make_input(samples, unknown_length=True), samples)


def test_known_length_ignores_trailing_samples():
    samples = [12000, 12001, 11999, 12002, 11998]
    trailing = [-30000, -30000, -30000]
    assert_correct(
        AGENT_PATH,
        make_input(samples, unknown_length=False, trailing=trailing),
        samples,
    )


def generate_fuzz_case(seed):
    random.seed(seed)
    unknown = random.random() < 0.5
    count = random.randint(1, 50000)
    dc_offset = random.choice([0, 15000, -15000, 30000, -30000])
    samples = []
    for _ in range(count):
        value = int(random.gauss(dc_offset, 1000))
        samples.append(max(-32768, min(32767, value)))
    return make_input(samples, unknown_length=unknown), samples


def test_derived_fuzz_results():
    # Expected answers are derived directly from each generated signal rather
    # than being skipped when an external oracle is absent.
    for seed in range(100):
        input_data, samples = generate_fuzz_case(seed)
        assert_correct(AGENT_PATH, input_data, samples)


def test_fixed_source_compiles_and_behaves_correctly():
    assert os.path.isfile(SOURCE_PATH), f"Missing fixed source: {SOURCE_PATH}"
    with tempfile.TemporaryDirectory() as tmpdir:
        built = os.path.join(tmpdir, "analyzer")
        compile_proc = subprocess.run(
            ["gcc", "-O2", SOURCE_PATH, "-lm", "-o", built],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_proc.returncode == 0, compile_proc.stderr.decode(
            "utf-8", errors="replace"
        )
        samples = [29999, 30000, 30001, 30000] * 5000
        assert_correct(built, make_input(samples, unknown_length=True), samples)


def test_diagnostic_artifacts_are_real_and_output_was_captured_exactly():
    with wave.open("/app/diagnostic_recording.wav", "rb") as wav_file:
        assert wav_file.getnchannels() == 1
        assert wav_file.getsampwidth() == 2
        raw_pcm = wav_file.readframes(wav_file.getnframes())

    expected_input = b"DIAG" + struct.pack("<I", 0xFFFFFFFF) + (b"\x00" * 24) + raw_pcm
    with open(INPUT_PATH, "rb") as input_file:
        actual_input = input_file.read()
    assert actual_input == expected_input, (
        "test_input.bin is not the required custom header followed by the "
        "recording's raw 16-bit PCM"
    )

    proc = subprocess.run(
        [AGENT_PATH, INPUT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    with open(OUTPUT_PATH, "rb") as output_file:
        saved_output = output_file.read()
    assert saved_output == proc.stdout, "diagnostic_output.txt is not the exact stdout"

    samples = [x[0] for x in struct.iter_unpack("<h", raw_pcm)]
    match = OUTPUT_RE.fullmatch(proc.stdout.decode("utf-8", errors="strict"))
    assert match, "Diagnostic output does not have the required format"
    expected_rms, expected_variance = expected_metrics(samples)
    assert float(match.group(1)) == pytest.approx(expected_rms, abs=0.0001)
    assert float(match.group(2)) == pytest.approx(expected_variance, abs=0.02)


def test_regression_script_compiles_and_produces_working_analyzer():
    with open(REGRESSION_PATH, "r", encoding="utf-8", errors="replace") as script_file:
        script = script_file.read()
    assert re.search(r"(?:^|[\s;/])(?:gcc|cc)(?:\s|$)", script), (
        "run_regression.sh does not invoke a C compiler"
    )
    assert "audio_analyzer.c" in script, (
        "run_regression.sh does not compile audio_analyzer.c"
    )

    # Removing the existing binary ensures the script must recreate it rather
    # than merely succeeding while relying on the previously compiled artifact.
    os.unlink(AGENT_PATH)
    proc = subprocess.run(
        ["bash", REGRESSION_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, (
        f"Regression script failed with {proc.returncode}\n"
        f"stdout: {proc.stdout.decode('utf-8', errors='replace')}\n"
        f"stderr: {proc.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(AGENT_PATH), "Regression script did not rebuild the analyzer"
    assert os.access(AGENT_PATH, os.X_OK), "Rebuilt analyzer is not executable"

    samples = [30000, 30001] * 10000
    assert_correct(AGENT_PATH, make_input(samples, unknown_length=True), samples)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
