#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import wave
import secrets
import tempfile
import shutil
import math
import numpy as np
import pytest
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def parse_single_float(stdout, source):
    try:
        value = float(stdout.strip())
    except ValueError:
        pytest.fail(f"{source} output could not be parsed as a float. Output was: {stdout.strip()}")
    assert math.isfinite(value), f"{source} returned a non-finite value: {value}"
    return value


def test_optimized_monitor_exists():
    assert os.path.isfile("/home/user/optimized_monitor.sh"), "The script /home/user/optimized_monitor.sh does not exist."


def test_dependency_conflict_is_fixed_and_setup_succeeds():
    requirements_path = "/app/requirements.txt"
    setup_path = "/app/setup.sh"
    assert os.path.isfile(requirements_path), f"{requirements_path} is missing."
    assert os.path.isfile(setup_path), f"{setup_path} is missing."

    seen = {}
    with open(requirements_path, encoding="utf-8") as requirements:
        for line in requirements:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("-"):
                continue
            requirement = Requirement(line)
            name = canonicalize_name(requirement.name)
            specification = str(requirement.specifier)
            if name in seen:
                assert seen[name] == specification, (
                    f"Conflicting requirements remain for {name}: "
                    f"{seen[name]!r} and {specification!r}"
                )
            seen[name] = specification

    try:
        result = subprocess.run(
            ["bash", setup_path], capture_output=True, text=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/app/setup.sh did not complete within 120 seconds")
    assert result.returncode == 0, (
        f"/app/setup.sh failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_optimized_monitor_accuracy_and_performance():
    audio_file = '/app/stream.wav'
    assert os.path.isfile(audio_file), f"{audio_file} is missing."

    # Compute ground truth
    with wave.open(audio_file, 'rb') as wf:
        frames = wf.readframes(wf.getnframes())
        samples = np.frombuffer(frames, dtype=np.int16)
        expected_energy = np.sum(samples.astype(np.float64) ** 2)

    # Run agent script
    script_path = '/home/user/optimized_monitor.sh'
    start = time.time()
    result = subprocess.run(['bash', script_path], capture_output=True, text=True)
    duration = time.time() - start

    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    try:
        agent_energy = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Script output could not be parsed as a float. Output was: {result.stdout.strip()}")

    # Check accuracy
    error = abs(agent_energy - expected_energy) / expected_energy if expected_energy != 0 else abs(agent_energy)
    assert error < 0.01, f"Energy calculation is incorrect. Expected ~{expected_energy}, got {agent_energy}"

    # Check metric threshold
    assert duration <= 0.5, f"Execution time {duration:.3f}s exceeded threshold of 0.5s"


def test_randomized_audio_and_malformed_metadata_are_processed():
    audio_file = "/app/stream.wav"
    process_path = "/app/process.py"
    assert os.path.isfile(process_path), f"{process_path} is missing."

    with tempfile.NamedTemporaryFile(delete=False) as backup:
        backup_path = backup.name
    shutil.copyfile(audio_file, backup_path)

    try:
        sample_count = 1000 + secrets.randbelow(4001)
        raw = secrets.token_bytes(sample_count * 2)
        samples = np.frombuffer(raw, dtype='<i2')
        expected_energy = sum(int(sample) * int(sample) for sample in samples)

        generated_path = audio_file + ".verifier_tmp"
        with wave.open(generated_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(44100)
            wf.writeframes(raw)
        with open(generated_path, "ab") as output:
            output.write(b"TAGcorrupted_" + secrets.token_bytes(47))
        os.replace(generated_path, audio_file)

        start = time.time()
        result = subprocess.run(
            ["bash", "/home/user/optimized_monitor.sh"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        duration = time.time() - start
        assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"
        agent_energy = parse_single_float(result.stdout, "optimized monitor")
        assert abs(agent_energy - expected_energy) <= 0.5, (
            f"Randomized audio energy is incorrect. Expected {expected_energy}, got {agent_energy}"
        )
        assert duration <= 0.5, f"Execution time {duration:.3f}s exceeded threshold of 0.5s"

        # Restore the generated case in case the wrapper altered it, then exercise
        # the repaired parser directly to ensure malformed trailing metadata no
        # longer causes a loop or is treated as PCM audio.
        with wave.open(generated_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(44100)
            wf.writeframes(raw)
        with open(generated_path, "ab") as output:
            output.write(b"TAGcorrupted_" + secrets.token_bytes(47))
        os.replace(generated_path, audio_file)

        try:
            parser_result = subprocess.run(
                ["python3", process_path],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("/app/process.py hung while parsing malformed trailing metadata")
        assert parser_result.returncode == 0, (
            f"/app/process.py failed.\nstdout:\n{parser_result.stdout}"
            f"\nstderr:\n{parser_result.stderr}"
        )
        parser_energy = parse_single_float(parser_result.stdout, "/app/process.py")
        assert abs(parser_energy - expected_energy) <= 0.5, (
            f"Parser included metadata or computed the wrong energy. "
            f"Expected {expected_energy}, got {parser_energy}"
        )
    finally:
        shutil.copyfile(backup_path, audio_file)
        os.unlink(backup_path)
        if os.path.exists(audio_file + ".verifier_tmp"):
            os.unlink(audio_file + ".verifier_tmp")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
