#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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
import importlib.util
import math
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import wave

import pytest
import requests

CODE_DIR = Path('/home/user/voice_math_api')
PREPROCESS = CODE_DIR / 'preprocess.sh'
MATH_ENGINE = CODE_DIR / 'math_engine.py'
PROCESSED = Path('/tmp/processed.wav')
URL = 'http://localhost:8080/calculate'


def expected_roots(a, b, c):
    discriminant = b * b - 4 * a * c
    if discriminant < 0:
        return []
    if discriminant == 0:
        return [-b / (2 * a)]
    return sorted([
        (-b - math.sqrt(discriminant)) / (2 * a),
        (-b + math.sqrt(discriminant)) / (2 * a),
    ])


def assert_roots(actual, expected):
    assert isinstance(actual, list), f"Expected roots to be a list, got {type(actual)}"
    assert len(actual) == len(expected), f"Expected {expected}, got {actual}"
    assert actual == sorted(actual), f"Roots are not in ascending order: {actual}"
    for got, want in zip(actual, expected):
        assert isinstance(got, (int, float)) and not isinstance(got, bool), f"Non-numeric root: {got!r}"
        assert math.isclose(got, want, rel_tol=1e-7, abs_tol=1e-7), f"Expected {want}, got {got}"


def post_with_retry(payload):
    max_retries = 5
    for i in range(max_retries):
        try:
            return requests.post(URL, json=payload, timeout=2)
        except requests.exceptions.RequestException as exc:
            if i == max_retries - 1:
                pytest.fail(f"Failed to connect to the API on port 8080: {exc}")
            time.sleep(1)


def write_wav(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(8000)
        wav.writeframes(secrets.token_bytes(320))


def test_required_artifacts_exist():
    assert MATH_ENGINE.is_file(), f"Missing regular file: {MATH_ENGINE}"
    assert PREPROCESS.is_file(), f"Missing regular file: {PREPROCESS}"
    assert os.access(PREPROCESS, os.X_OK), f"Preprocessing script is not executable: {PREPROCESS}"


def test_math_engine_general_quadratic_logic():
    spec = importlib.util.spec_from_file_location('submitted_math_engine', MATH_ENGINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'calculate_roots', None)), 'calculate_roots is missing or not callable'

    cases = [
        (1, 0, -4),       # two roots
        (1, -6, 9),       # repeated root
        (1, 0, 4),        # no real roots
        (-2, 2, 4),       # negative leading coefficient
    ]
    for _ in range(8):
        a = secrets.choice([n for n in range(-7, 8) if n])
        r1 = secrets.randbelow(19) - 9
        r2 = secrets.randbelow(19) - 9
        b = -a * (r1 + r2)
        c = a * r1 * r2
        cases.append((a, b, c))

    for a, b, c in cases:
        actual = module.calculate_roots(a, b, c)
        assert_roots(actual, expected_roots(a, b, c))


def test_preprocess_handles_arbitrary_valid_paths():
    token = secrets.token_hex(6)
    with tempfile.TemporaryDirectory(prefix=f'voice math {token} ') as tmp:
        base = Path(tmp)
        paths = [
            base / 'ordinary.wav',
            base / 'incident with several spaces.wav',
            base / 'brackets[12] and glob*.wav',
            base / "quote's;audio.wav",
            base / '-leading-dash.wav',
        ]
        for index, source in enumerate(paths):
            write_wav(source)
            expected = source.read_bytes()
            if PROCESSED.exists():
                PROCESSED.unlink()
            result = subprocess.run(
                ['bash', str(PREPROCESS), str(source)],
                cwd=str(CODE_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert result.returncode == 0, (
                f"preprocess.sh failed for valid path {source!s}: "
                f"{result.stderr.decode(errors='replace')}"
            )
            assert PROCESSED.is_file(), 'preprocess.sh did not create /tmp/processed.wav'
            assert PROCESSED.read_bytes() == expected, f"Preprocessed output differs from input for {source!s}"


def test_api_calculates_correct_roots():
    payload = {'audio_path': '/app/incident report 01.wav'}
    response = post_with_retry(payload)

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert 'roots' in data, f"Response JSON missing 'roots' key. Got: {data}"
    roots = data['roots']
    assert isinstance(roots, list), f"Expected 'roots' to be a list, got {type(roots)}"
    expected = [-2.0, 2.0]
    assert len(roots) == 2, f"Expected 2 roots, got {len(roots)}: {roots}"
    sorted_roots = sorted(roots)
    assert abs(sorted_roots[0] - expected[0]) < 1e-5, f"First root incorrect. Expected {expected[0]}, got {sorted_roots[0]}"
    assert abs(sorted_roots[1] - expected[1]) < 1e-5, f"Second root incorrect. Expected {expected[1]}, got {sorted_roots[1]}"
    assert roots == sorted_roots, f"API roots are not in ascending order: {roots}"


def test_api_uses_general_preprocessing_and_math_path():
    token = secrets.token_hex(8)
    audio_path = Path('/app') / f'qa upload {token} [final].wav'
    try:
        write_wav(audio_path)
        response = post_with_retry({'audio_path': str(audio_path)})
        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
        assert set(data.keys()) == {'roots'}, f"Unexpected response JSON: {data}"
        assert_roots(data['roots'], expected_roots(1.0, -3.0, 2.0))
        assert PROCESSED.is_file(), 'API did not run the required preprocessing output path'
        assert PROCESSED.read_bytes() == audio_path.read_bytes(), 'API preprocessing output does not match requested audio'
    finally:
        if audio_path.exists():
            audio_path.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
