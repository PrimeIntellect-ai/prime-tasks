#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
import tempfile
import time

import numpy as np
from scipy.io import wavfile
import pytest

SCRIPT_PATH = "/home/user/wave_math.py"
REF_AUDIO_PATH = "/app/reference_audio.wav"
PROCESSED_AUDIO_PATH = "/home/user/processed_audio.wav"
EVIL_CORPUS_PATH = "/tests/corpora/evil_expressions.txt"
CLEAN_CORPUS_PATH = "/tests/corpora/clean_expressions.txt"


def run_tool(input_wav, output_wav, expression, timeout=10):
    return subprocess.run(
        ["python3", SCRIPT_PATH, input_wav, output_wav, expression],
        capture_output=True,
        timeout=timeout,
    )


def test_processed_audio_correctness():
    assert os.path.isfile(PROCESSED_AUDIO_PATH), f"Processed audio file {PROCESSED_AUDIO_PATH} not found."

    rate, data = wavfile.read(REF_AUDIO_PATH)
    expected_data = data * 2.0
    act_rate, act_data = wavfile.read(PROCESSED_AUDIO_PATH)

    assert act_rate == rate, f"Sample rate mismatch: expected {rate}, got {act_rate}"
    np.testing.assert_allclose(
        act_data,
        expected_data,
        err_msg="Processed audio data does not match the expected output of x * 2.0",
    )


def test_source_uses_numpy():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    imports_numpy = any(
        (isinstance(node, ast.Import) and any(alias.name == "numpy" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "numpy")
        for node in ast.walk(tree)
    )
    assert imports_numpy, "wave_math.py must use NumPy for vectorized waveform processing"


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    assert os.path.isfile(EVIL_CORPUS_PATH), f"Evil corpus {EVIL_CORPUS_PATH} not found."
    assert os.path.isfile(CLEAN_CORPUS_PATH), f"Clean corpus {CLEAN_CORPUS_PATH} not found."

    with open(EVIL_CORPUS_PATH, "r", encoding="utf-8") as f:
        evil_exprs = [line.strip() for line in f if line.strip()]
    with open(CLEAN_CORPUS_PATH, "r", encoding="utf-8") as f:
        clean_exprs = [line.strip() for line in f if line.strip()]

    evil_bypassed = []
    evil_wrong_status = []
    clean_failed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        out_wav = os.path.join(tmpdir, "out.wav")

        for expr in evil_exprs:
            res = run_tool(REF_AUDIO_PATH, out_wav, expr)
            if res.returncode == 0:
                evil_bypassed.append(expr)
            if res.returncode != 1:
                evil_wrong_status.append((expr, res.returncode))

        for expr in clean_exprs:
            if os.path.exists(out_wav):
                os.remove(out_wav)
            res = run_tool(REF_AUDIO_PATH, out_wav, expr)
            if res.returncode != 0 or not os.path.isfile(out_wav):
                clean_failed.append(expr)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_exprs)} evil bypassed: {evil_bypassed}")
    if evil_wrong_status:
        error_msgs.append(f"unsafe expressions must exit with status 1: {evil_wrong_status}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_exprs)} clean modified/failed: {clean_failed}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_valid_expressions_are_evaluated_correctly():
    rng = secrets.SystemRandom()
    rate = 16000
    data = np.array([rng.randrange(-6, 7) for _ in range(257)], dtype=np.int16)

    a = rng.uniform(0.21, 1.79)
    b = rng.uniform(-2.4, 2.4)
    c = rng.uniform(1.1, 3.2)
    expressions = [
        (f"x * {a!r} + {b!r}", lambda x: x * a + b),
        (f"sin(x * {a!r}) * {c!r}", lambda x: np.sin(x * a) * c),
        (f"cos(x / {c!r}) + {b!r}", lambda x: np.cos(x / c) + b),
        (f"x**2 * {a!r} + cos(x)", lambda x: x**2 * a + np.cos(x)),
        (f"(x + {b!r}) / {c!r}", lambda x: (x + b) / c),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_wav = os.path.join(tmpdir, "generated_input.wav")
        wavfile.write(input_wav, rate, data)

        for index, (expr, expected_fn) in enumerate(expressions):
            output_wav = os.path.join(tmpdir, f"generated_output_{index}.wav")
            res = run_tool(input_wav, output_wav, expr)
            assert res.returncode == 0, (
                f"valid generated expression failed: {expr!r}; stderr={res.stderr.decode(errors='replace')}"
            )
            assert os.path.isfile(output_wav), f"no output for valid expression {expr!r}"
            out_rate, actual = wavfile.read(output_wav)
            expected = np.asarray(expected_fn(data), dtype=np.int16)
            assert out_rate == rate
            np.testing.assert_array_equal(actual, expected, err_msg=f"wrong result for {expr!r}")


def test_generated_unsafe_expressions_are_rejected_without_side_effects():
    nonce = secrets.token_hex(12)
    with tempfile.TemporaryDirectory() as tmpdir:
        input_wav = os.path.join(tmpdir, "input.wav")
        output_wav = os.path.join(tmpdir, "output.wav")
        marker = os.path.join(tmpdir, f"marker_{nonce}")
        wavfile.write(input_wav, 8000, np.arange(-8, 8, dtype=np.int16))

        qmarker = repr(marker)
        payloads = [
            f"__import__('os').system('touch ' + {qmarker})",
            f"(__import__)('pathlib').Path({qmarker}).write_text('owned')",
            f"open({qmarker}, 'w').write('owned')",
            f"getattr(__import__('os'), 'system')('touch ' + {qmarker})",
            "(lambda y: y)(x)",
            "x.__class__.__mro__",
            "vars(__builtins__)",
            "np.__dict__['load']('/tmp/not_there.npy', allow_pickle=True)",
            f"compile(\"open({qmarker}, 'w').write('owned')\", '<x>', 'eval')",
        ]

        for expr in payloads:
            if os.path.exists(marker):
                os.remove(marker)
            if os.path.exists(output_wav):
                os.remove(output_wav)
            res = run_tool(input_wav, output_wav, expr)
            assert res.returncode == 1, (
                f"unsafe generated expression did not exit with status 1: {expr!r} "
                f"(status {res.returncode})"
            )
            assert not os.path.exists(marker), f"unsafe expression produced a side effect: {expr!r}"


def test_five_minute_audio_is_vectorized_and_under_two_seconds():
    rate = 44100
    sample_count = rate * 5 * 60
    pattern = np.arange(-100, 101, dtype=np.int16)
    data = np.tile(pattern, (sample_count + len(pattern) - 1) // len(pattern))[:sample_count]
    coefficient = secrets.SystemRandom().uniform(1.05, 1.35)
    expression = f"x * {coefficient!r}"

    with tempfile.TemporaryDirectory() as tmpdir:
        input_wav = os.path.join(tmpdir, "five_minutes.wav")
        output_wav = os.path.join(tmpdir, "five_minutes_out.wav")
        wavfile.write(input_wav, rate, data)

        start = time.perf_counter()
        res = run_tool(input_wav, output_wav, expression, timeout=4)
        elapsed = time.perf_counter() - start

        assert res.returncode == 0, res.stderr.decode(errors="replace")
        assert os.path.isfile(output_wav)
        assert elapsed < 2.0, f"processing five minutes took {elapsed:.3f}s; required under 2 seconds"

        out_rate, actual = wavfile.read(output_wav)
        assert out_rate == rate
        expected = np.asarray(data * coefficient, dtype=np.int16)
        np.testing.assert_array_equal(actual, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
