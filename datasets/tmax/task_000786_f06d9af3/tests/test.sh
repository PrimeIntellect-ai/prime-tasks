#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import pathlib
import random
import re
import struct
import subprocess
import tempfile
import time
import wave

import pytest

PROJECT = pathlib.Path("/home/user/project")
SAMPLE = "/app/sample_audio.wav"
BUILT_LIBRARY = None


@pytest.fixture(scope="session", autouse=True)
def build_and_load_library():
    global BUILT_LIBRARY

    build_dir = pathlib.Path(tempfile.mkdtemp(prefix="audio_analyzer_build_"))
    configure = subprocess.run(
        ["cmake", "-S", str(PROJECT), "-B", str(build_dir)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert configure.returncode == 0, (
        "CMake configuration failed:\n" + configure.stdout + configure.stderr
    )

    build = subprocess.run(
        ["cmake", "--build", str(build_dir), "--config", "Release", "-j2"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, "CMake build failed:\n" + build.stdout + build.stderr

    candidates = list(build_dir.rglob("libaudio_analyzer.so"))
    assert candidates, "The CMake build did not produce libaudio_analyzer.so."

    errors = []
    for candidate in candidates:
        try:
            library = ctypes.CDLL(str(candidate))
            function = library.analyze_audio_energy
            function.argtypes = [ctypes.c_char_p]
            function.restype = ctypes.c_double
            BUILT_LIBRARY = (library, function, candidate)
            break
        except (OSError, AttributeError) as exc:
            errors.append(f"{candidate}: {exc}")

    assert BUILT_LIBRARY is not None, (
        "No built library exported the required unmangled C-ABI symbol "
        "analyze_audio_energy(const char*). Errors: " + "; ".join(errors)
    )


def test_files_exist():
    assert os.path.isfile(PROJECT / "CMakeLists.txt"), "CMakeLists.txt is missing."
    assert os.path.isfile(PROJECT / "run_analysis.py"), "run_analysis.py is missing."

    cpp_files = []
    for suffix in ("*.cpp", "*.cc", "*.cxx"):
        cpp_files.extend(PROJECT.rglob(suffix))
    assert cpp_files, "No C++ implementation source file was found."

    source_text = "\n".join(
        path.read_text(errors="ignore") for path in cpp_files if path.is_file()
    )
    assert re.search(r"\b(class|struct)\s+[A-Za-z_]\w*", source_text), (
        "The C++ sources do not define the required custom data structure."
    )


def test_shared_library_exists():
    # Preserve the original requirement that an agent-built library is present
    # somewhere in the project directory.
    found_so = False
    for root, dirs, files in os.walk(PROJECT):
        if "libaudio_analyzer.so" in files:
            found_so = True
            break
    assert found_so, (
        "libaudio_analyzer.so was not found in /home/user/project or its subdirectories."
    )


def _write_sine(path, sample_rate, frame_count, amplitude, frequency):
    samples = []
    for i in range(frame_count):
        value = int(round(amplitude * math.sin(2.0 * math.pi * frequency * i / sample_rate)))
        value = max(-32768, min(32767, value))
        samples.append(value)

    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(struct.pack("<" + "h" * len(samples), *samples))
    return sum(value * value for value in samples)


def _write_silence(path, sample_rate, frame_count):
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(b"\x00\x00" * frame_count)


def _call(path):
    function = BUILT_LIBRARY[1]
    result = function(os.fsencode(path))
    assert math.isfinite(result), f"Analysis returned a non-finite value for {path}: {result}"
    assert result >= 0.0, f"Energy must be nonnegative, got {result} for {path}"
    return result


def _assert_ratio(observed_a, observed_b, expected_ratio, relative_tolerance, description):
    assert observed_b > 0.0, f"Zero denominator while checking {description}."
    observed_ratio = observed_a / observed_b
    lower = expected_ratio * (1.0 - relative_tolerance)
    upper = expected_ratio * (1.0 + relative_tolerance)
    assert lower <= observed_ratio <= upper, (
        f"Incorrect {description}: observed ratio {observed_ratio:.6g}, "
        f"expected approximately {expected_ratio:.6g}."
    )


def test_c_abi_computes_audio_energy_for_derived_inputs():
    rng = random.SystemRandom()
    sample_rate = 8000
    frames = 16384
    amplitude_low = rng.randint(1200, 2200)
    amplitude_high = rng.randint(5000, 7500)
    frequency_a = rng.randint(330, 900)
    frequency_b = rng.randint(1400, 2600)

    with tempfile.TemporaryDirectory(prefix="verifier_audio_") as directory:
        directory = pathlib.Path(directory)
        low_path = directory / "tone_low.wav"
        high_path = directory / "tone_high.wav"
        long_path = directory / "tone_long.wav"
        other_frequency_path = directory / "tone_other_frequency.wav"
        silence_path = directory / "silence.wav"

        pcm_low = _write_sine(low_path, sample_rate, frames, amplitude_low, frequency_a)
        pcm_high = _write_sine(high_path, sample_rate, frames, amplitude_high, frequency_a)
        pcm_long = _write_sine(long_path, sample_rate, frames * 2, amplitude_low, frequency_a)
        pcm_other = _write_sine(
            other_frequency_path, sample_rate, frames, amplitude_low, frequency_b
        )
        _write_silence(silence_path, sample_rate, frames)

        energy_low = _call(low_path)
        energy_high = _call(high_path)
        energy_long = _call(long_path)
        energy_other = _call(other_frequency_path)
        energy_silence = _call(silence_path)

        assert energy_low > 0.0, "A non-silent PCM tone produced zero energy."

        # Parseval's relation makes total STFT energy scale with PCM squared
        # amplitude, independent of the implementation's fixed normalization.
        _assert_ratio(
            energy_high,
            energy_low,
            pcm_high / pcm_low,
            0.12,
            "squared-amplitude energy scaling",
        )
        _assert_ratio(
            energy_long,
            energy_low,
            pcm_long / pcm_low,
            0.20,
            "whole-file duration scaling",
        )
        _assert_ratio(
            energy_other,
            energy_low,
            pcm_other / pcm_low,
            0.20,
            "full-spectrum frequency coverage",
        )
        assert energy_silence <= max(1e-9, energy_low * 1e-7), (
            f"Silence produced substantial energy: {energy_silence}"
        )


def _parse_two_numeric_lines(stdout):
    lines = stdout.splitlines()
    assert len(lines) == 2 and all(line.strip() for line in lines), (
        "run_analysis.py must print exactly two nonempty lines: one result and one time. "
        f"Got: {stdout!r}"
    )
    number_pattern = re.compile(
        r"(?<![A-Za-z0-9_.])[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
    )
    values = []
    for line in lines:
        matches = number_pattern.findall(line)
        assert len(matches) == 1, f"Each output line must contain exactly one numeric value: {line!r}"
        value = float(matches[0])
        assert math.isfinite(value), f"Output contains a non-finite value: {line!r}"
        values.append(value)
    return values


def test_execution_time_and_output():
    script_path = "/home/user/project/run_analysis.py"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    start = time.perf_counter()
    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    elapsed_ms = (time.perf_counter() - start) * 1000.0

    assert result.returncode == 0, f"run_analysis.py failed with error:\n{result.stderr}"
    assert result.stdout.strip(), "run_analysis.py did not produce any output."
    assert elapsed_ms <= 50.0, (
        f"Execution time was {elapsed_ms:.2f} ms, which exceeds the 50.0 ms threshold."
    )

    values = _parse_two_numeric_lines(result.stdout)

    function = BUILT_LIBRARY[1]
    direct_start = time.perf_counter()
    expected_energy = function(os.fsencode(SAMPLE))
    direct_elapsed_ms = (time.perf_counter() - direct_start) * 1000.0
    assert math.isfinite(expected_energy) and expected_energy >= 0.0
    assert direct_elapsed_ms <= 50.0, (
        f"analyze_audio_energy itself took {direct_elapsed_ms:.2f} ms, exceeding 50.0 ms."
    )

    def energy_matches(value):
        return math.isclose(value, expected_energy, rel_tol=1e-3, abs_tol=1e-6)

    valid_layout = False
    for energy_index, time_index in ((0, 1), (1, 0)):
        if energy_matches(values[energy_index]) and 0.0 <= values[time_index] <= 50.0:
            valid_layout = True
            break
    assert valid_layout, (
        "The two output lines must report the library's actual energy result and an "
        f"execution time no greater than 50 ms. Output values: {values}; "
        f"direct library result: {expected_energy}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
