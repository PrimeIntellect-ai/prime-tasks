#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import wave
from array import array
from pathlib import Path

import pytest


def test_peak_time_metric():
    """Check if the peak time is within the acceptable threshold."""
    path = "/home/user/peak_time.txt"
    assert os.path.isfile(path), f"Expected file at {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    try:
        agent_value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {path} as a float: '{content}'")

    reference_value = 12.500
    threshold = 0.05
    error = abs(agent_value - reference_value)

    assert error < threshold, f"Absolute error {error} is not less than threshold {threshold} (Agent value: {agent_value}, Reference: {reference_value})"


def test_deployment_yaml_updated():
    """Check if the deployment.yaml has been updated to replicas: 3."""
    path = "/home/user/manifests/deployment.yaml"
    assert os.path.isfile(path), f"Expected file at {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "replicas: 3" in content, f"File {path} does not contain 'replicas: 3' as expected. Content:\n{content}"
    assert "replicas: 1" not in content, f"File {path} still contains 'replicas: 1'."


def test_operator_fstab_conf():
    """Check if the fstab config file contains the correct bind mount entry."""
    path = "/home/user/operator_fstab.conf"
    assert os.path.isfile(path), f"Expected file at {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    fields = content.split()
    assert len(fields) == 6, f"Expected 6 fields in fstab entry, found {len(fields)}: '{content}'"
    assert fields[0] == "/home/user/manifests", f"Expected first field to be '/home/user/manifests', got '{fields[0]}'"
    assert fields[1] == "/var/lib/k8s/active_manifests", f"Expected second field to be '/var/lib/k8s/active_manifests', got '{fields[1]}'"
    assert fields[2] == "none", f"Expected third field to be 'none', got '{fields[2]}'"

    opts = fields[3].split(',')
    assert set(opts) == {"bind", "ro"}, f"Expected options to be 'bind,ro', got '{fields[3]}'"
    assert fields[4] == "0", f"Expected fifth field to be '0', got '{fields[4]}'"
    assert fields[5] == "0", f"Expected sixth field to be '0', got '{fields[5]}'"


def _write_test_wav(path, sample_rate, duration_samples, burst_start):
    rng = random.SystemRandom()
    samples = array('h', (rng.randint(-20, 20) for _ in range(duration_samples)))
    for i in range(burst_start, burst_start + sample_rate):
        samples[i] = 20000 if i % 2 == 0 else -20000

    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(samples.tobytes())

    absolute = [abs(value) for value in samples]
    current = sum(absolute[:sample_rate])
    best_sum = current
    best_start = 0
    for start in range(1, len(samples) - sample_rate + 1):
        current += absolute[start + sample_rate - 1] - absolute[start - 1]
        if current > best_sum:
            best_sum = current
            best_start = start
    return best_start / sample_rate


def test_analyzer_artifacts_and_behavior(tmp_path):
    source = Path('/home/user/telemetry_analyzer.c')
    analyzer = Path('/home/user/telemetry_analyzer')

    assert source.is_file(), f"Expected C source at {source} is missing."
    assert source.stat().st_size > 0, f"C source at {source} is empty."
    assert analyzer.is_file(), f"Expected compiled analyzer at {analyzer} is missing."
    assert os.access(analyzer, os.X_OK), f"Analyzer at {analyzer} is not executable."
    assert analyzer.read_bytes()[:4] == b'\x7fELF', f"Analyzer at {analyzer} is not a compiled ELF executable."

    rng = random.SystemRandom()
    cases = [
        (8000, rng.randrange(8000, 30000)),
        (11025, rng.randrange(60000, 85000)),
    ]
    for index, (sample_rate, burst_start) in enumerate(cases):
        duration_samples = burst_start + sample_rate + rng.randrange(2000, 7000)
        wav_path = tmp_path / f'telemetry_{index}.wav'
        expected = _write_test_wav(wav_path, sample_rate, duration_samples, burst_start)
        result = subprocess.run(
            [str(analyzer), str(wav_path)],
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Analyzer failed on {wav_path}: {result.stderr}"
        try:
            actual = float(result.stdout.strip())
        except ValueError:
            pytest.fail(f"Analyzer output is not a floating-point value: {result.stdout!r}")
        assert math.isfinite(actual), f"Analyzer returned a non-finite value: {actual}"
        assert abs(actual - expected) < 0.01, f"Analyzer returned {actual}, expected {expected} for generated WAV"


def test_operator_executes_analyzer_and_applies_both_branches(tmp_path):
    operator = Path('/home/user/operator.sh')
    analyzer = Path('/home/user/telemetry_analyzer')
    yaml_path = Path('/home/user/manifests/deployment.yaml')
    peak_path = Path('/home/user/peak_time.txt')
    marker = Path('/tmp/operator_analyzer_marker')
    control = Path('/tmp/operator_probe_value')
    backup = Path('/tmp/original_telemetry_analyzer')

    assert operator.is_file(), f"Expected operator script at {operator} is missing."
    assert operator.stat().st_size > 0, f"Operator script at {operator} is empty."

    original_yaml = yaml_path.read_bytes()
    original_peak = peak_path.read_bytes() if peak_path.exists() else None
    if backup.exists():
        backup.unlink()

    probe_source = tmp_path / 'operator_probe.c'
    probe_source.write_text(r'''#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "/app/telemetry.wav") != 0) return 9;
    FILE *marker = fopen("/tmp/operator_analyzer_marker", "w");
    if (!marker) return 8;
    fputs("called", marker);
    fclose(marker);
    FILE *value = fopen("/tmp/operator_probe_value", "r");
    if (!value) return 7;
    char buffer[128];
    if (!fgets(buffer, sizeof(buffer), value)) return 6;
    fclose(value);
    fputs(buffer, stdout);
    return 0;
}
''')

    os.replace(analyzer, backup)
    try:
        compile_result = subprocess.run(
            ['gcc', str(probe_source), '-o', str(analyzer)],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"Could not build verifier probe: {compile_result.stderr}"

        yaml_path.write_text('apiVersion: apps/v1\nkind: Deployment\nspec:\n  replicas: 1\n')
        control.write_text('6.375\n')
        marker.unlink(missing_ok=True)
        result = subprocess.run(['bash', str(operator)], text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, f"Operator failed: {result.stderr}"
        assert marker.is_file(), "Operator did not execute /home/user/telemetry_analyzer on /app/telemetry.wav."
        assert peak_path.read_text().strip() == '6.375', "Operator did not save the analyzer output to peak_time.txt."
        high_yaml = yaml_path.read_text()
        assert 'replicas: 3' in high_yaml, "Operator did not scale to 3 replicas for a peak time greater than 5.0."
        assert 'replicas: 1' not in high_yaml, "Operator left replicas at 1 for a peak time greater than 5.0."

        yaml_path.write_text('apiVersion: apps/v1\nkind: Deployment\nspec:\n  replicas: 1\n')
        control.write_text('2.250\n')
        marker.unlink(missing_ok=True)
        result = subprocess.run(['bash', str(operator)], text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, f"Operator failed: {result.stderr}"
        assert marker.is_file(), "Operator did not execute the analyzer on its second run."
        assert peak_path.read_text().strip() == '2.250', "Operator did not save the second analyzer output."
        low_yaml = yaml_path.read_text()
        assert 'replicas: 1' in low_yaml, "Operator scaled when the peak time was not greater than 5.0."
        assert 'replicas: 3' not in low_yaml, "Operator incorrectly changed replicas to 3 for a low peak time."
    finally:
        if analyzer.exists():
            analyzer.unlink()
        if backup.exists():
            os.replace(backup, analyzer)
        yaml_path.write_bytes(original_yaml)
        if original_peak is None:
            peak_path.unlink(missing_ok=True)
        else:
            peak_path.write_bytes(original_peak)
        marker.unlink(missing_ok=True)
        control.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
