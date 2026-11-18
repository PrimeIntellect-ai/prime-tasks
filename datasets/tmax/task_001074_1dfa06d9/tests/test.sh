#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import tempfile
import time
import wave

import pytest

SCRIPT_PATH = "/home/user/fast_decode.sh"
AUDIO_PATH = "/app/audio/telemetry.wav"
EXPECTED = "libcore-2.1.0 libnet-1.4.2"


def run_decoder(audio_path, timeout=10):
    return subprocess.run(
        ["/bin/bash", SCRIPT_PATH, audio_path],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def encoded_block(nibble, valid=True):
    d1 = (nibble >> 3) & 1
    d2 = (nibble >> 2) & 1
    d3 = (nibble >> 1) & 1
    d4 = nibble & 1
    parity = [d1 ^ d2 ^ d3, d2 ^ d3 ^ d4,
              d1 ^ d3 ^ d4, d1 ^ d2 ^ d4]
    if not valid:
        parity[0] ^= 1
    return [d1, d2, d3, d4] + parity


def write_test_wav(path, text, seed):
    rng = random.Random(seed)
    bits = []
    for ch in text.encode("ascii"):
        for nibble in ((ch >> 4) & 0xF, ch & 0xF):
            # Invalid blocks must be discarded and must not disturb nibble pairing.
            if rng.random() < 0.45:
                bits.extend(encoded_block(rng.randrange(16), valid=False))
            bits.extend(encoded_block(nibble, valid=True))
    bits.extend(encoded_block(rng.randrange(16), valid=False))

    samples = []
    one_patterns = (
        [8000] * 8,
        [-10000] * 8,
        [7000, 9000] * 4,
        [-12000, -4000] * 4,
    )
    zero_patterns = (
        [0] * 8,
        [7999] * 8,
        [-5000, 5000] * 4,
        [-7999] * 8,
    )
    for bit in bits:
        samples.extend(rng.choice(one_patterns if bit else zero_patterns))

    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(8000)
        wav.writeframes(struct.pack("<{}h".format(len(samples)), *samples))


def test_fast_decode_performance_and_output():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    start_time = time.time()
    try:
        result = run_decoder(AUDIO_PATH)
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out after 10 seconds. Threshold is 2.0 seconds.")

    runtime = time.time() - start_time
    output = result.stdout.strip()

    assert result.returncode == 0, result.stderr
    assert output == EXPECTED, (
        f"Script output did not match expected.\nExpected: '{EXPECTED}'\nGot: '{output}'"
    )
    assert runtime <= 2.0, (
        f"Script execution took {runtime:.3f} seconds, which exceeds the 2.0 seconds threshold."
    )


def test_decoder_on_unseen_audio_and_invalid_parity():
    rng = random.SystemRandom()
    alphabet = "abcdefghijklmnopqrstuvwxyz"
    cases = []
    for _ in range(3):
        a = "".join(rng.choice(alphabet) for _ in range(7))
        b = "".join(rng.choice(alphabet) for _ in range(6))
        text = f"lib{a}-{rng.randrange(1,10)}.{rng.randrange(10)}.{rng.randrange(10)} lib{b}-{rng.randrange(1,10)}.{rng.randrange(10)}.{rng.randrange(10)}"
        cases.append((text, rng.randrange(1 << 63)))

    with tempfile.TemporaryDirectory() as tmpdir:
        for index, (expected, seed) in enumerate(cases):
            path = os.path.join(tmpdir, f"telemetry-{index}.wav")
            write_test_wav(path, expected, seed)
            try:
                result = run_decoder(path, timeout=5)
            except subprocess.TimeoutExpired:
                pytest.fail("Decoder timed out on an additional valid WAV input")
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected, (
                "Decoder failed on independently generated audio containing "
                "threshold, signed-sample, and invalid-parity cases.\n"
                f"Expected: {expected!r}\nGot: {result.stdout.strip()!r}"
            )


def test_makefile_compilation():
    src_dir = "/app/src"
    makefile_path = os.path.join(src_dir, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"

    result = subprocess.run(
        ["make", "-B"], cwd=src_dir, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "Running 'make' failed. The Makefile might still have incorrect paths.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    main_exec = os.path.join(src_dir, "main")
    assert os.path.isfile(main_exec), "Executable 'main' was not created after running make."
    assert os.access(main_exec, os.X_OK), "File 'main' was created but is not executable."


def test_makefile_actually_links_decoded_libraries():
    src_dir = "/app/src"
    main_c = os.path.join(src_dir, "main.c")
    main_exec = os.path.join(src_dir, "main")
    core_so = "/opt/libcore-2.1.0/libcore.so"
    net_so = "/opt/libnet-1.4.2/libnet.so"

    paths = [main_c, core_so, net_so]
    backups = {path: open(path, "rb").read() for path in paths}
    modes = {path: os.stat(path).st_mode for path in paths}
    rng = random.SystemRandom()
    core_value = rng.randrange(10000, 1000000000)
    net_value = rng.randrange(10000, 1000000000)

    try:
        core_build = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-x", "c", "-", "-o", core_so],
            input=f"int core_version_probe(void) {{ return {core_value}; }}\n",
            text=True, capture_output=True,
        )
        assert core_build.returncode == 0, core_build.stderr

        net_build = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-x", "c", "-", "-o", net_so],
            input=f"int net_version_probe(void) {{ return {net_value}; }}\n",
            text=True, capture_output=True,
        )
        assert net_build.returncode == 0, net_build.stderr

        with open(main_c, "w") as source:
            source.write(
                "int core_version_probe(void);\n"
                "int net_version_probe(void);\n"
                "int main(void) {\n"
                f"  return (core_version_probe() == {core_value} && "
                f"net_version_probe() == {net_value}) ? 0 : 1;\n"
                "}\n"
            )

        result = subprocess.run(
            ["make", "-B"], cwd=src_dir, capture_output=True, text=True
        )
        assert result.returncode == 0, (
            "The Makefile can build the original program but does not actually link "
            "the decoded libcore and libnet versions.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(main_exec) and os.access(main_exec, os.X_OK)

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = "/opt/libcore-2.1.0:/opt/libnet-1.4.2"
        executed = subprocess.run(
            [main_exec], cwd=src_dir, env=env, capture_output=True, text=True
        )
        assert executed.returncode == 0, (
            "The produced executable did not use the required decoded libraries. "
            f"Stderr: {executed.stderr}"
        )
    finally:
        for path, content in backups.items():
            with open(path, "wb") as restored:
                restored.write(content)
            os.chmod(path, modes[path])
        if os.path.exists(main_exec):
            os.remove(main_exec)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
