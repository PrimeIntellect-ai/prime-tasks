#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/decoder.py"
ENCRYPTED_PAYLOAD = [108, 99, 105, 112, 85, 83, 19, 83, 87, 82, 83, 90, 21, 160]


def expected_decode(data, key):
    return [((byte ^ key) - (index % 256)) & 0xFF for index, byte in enumerate(data)]


def run_decoder(key):
    try:
        return subprocess.run(
            ["python3", SCRIPT_PATH, str(key)],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The decoder.py script timed out. It likely still has an infinite recursion or loop.")


def load_decoder():
    spec = importlib.util.spec_from_file_location("submitted_decoder", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_flag_file_content():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"The file {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read()

    assert content == "FLAG{d3bug_m3}", f"The content of {flag_path} is incorrect. Found: {repr(content)}"


def test_decoder_script_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."

    result = run_decoder(42)
    assert result.returncode == 0, f"The decoder.py script failed to execute. Error: {result.stderr}"

    output = result.stdout.strip()
    assert output == "FLAG{d3bug_m3}", f"The decoder.py script did not output the correct flag. Found: {repr(output)}"


def test_decode_chunk_is_recursive_and_handles_generated_inputs():
    with open(SCRIPT_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=SCRIPT_PATH)

    functions = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == "decode_chunk"]
    assert functions, "decoder.py must define decode_chunk."
    recursive = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "decode_chunk"
        for node in ast.walk(functions[0])
    )
    assert recursive, "decode_chunk must remain a recursive decoder."

    decoder = load_decoder()
    assert callable(getattr(decoder, "decode_chunk", None)), "decode_chunk is not callable."

    rng = secrets.SystemRandom()
    cases = [([], rng.randrange(256))]
    for _ in range(12):
        data = [rng.randrange(256) for _ in range(rng.randrange(1, 65))]
        cases.append((data, rng.randrange(256)))

    for data, key in cases:
        result = []
        try:
            decoder.decode_chunk(data, 0, key, result)
        except RecursionError:
            pytest.fail("decode_chunk did not terminate on a generated input.")
        assert result == expected_decode(data, key), (
            f"decode_chunk produced incorrect bytes for key {key}: "
            f"expected {expected_decode(data, key)!r}, got {result!r}"
        )


def test_decoder_cli_with_generated_keys():
    rng = secrets.SystemRandom()
    keys = set()
    while len(keys) < 6:
        key = rng.randrange(256)
        if key != 42:
            keys.add(key)

    for key in keys:
        result = run_decoder(key)
        assert result.returncode == 0, f"decoder.py failed for key {key}: {result.stderr}"
        expected_text = "".join(chr(value) for value in expected_decode(ENCRYPTED_PAYLOAD, key))
        assert result.stdout == expected_text + "\n", (
            f"decoder.py produced incorrect output for generated key {key}. "
            f"Found: {result.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
