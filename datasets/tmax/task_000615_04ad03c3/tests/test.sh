#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import pytest

PROJECT = "/app/api-gateway-core"
ADDON = f"{PROJECT}/build/Release/validator.node"
RESULTS = "/app/benchmark_results.txt"


def test_addon_compiled():
    assert os.path.isfile(ADDON), f"Compiled addon not found at {ADDON}. The build configuration may still be broken or 'npm run build' was not executed."


def test_build_command_succeeds():
    result = subprocess.run(
        ["npm", "run", "build"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"npm run build failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(ADDON), f"Compiled addon not found at {ADDON} after npm run build."


def test_benchmark_results_file_exists():
    assert os.path.isfile(RESULTS), "/app/benchmark_results.txt is missing. Did you forget to save the benchmark output?"

    with open(RESULTS, "r", encoding="utf-8", newline="") as f:
        output = f.read()

    number = r"([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)"
    script_only = re.fullmatch(rf"Elapsed: {number}s\r?\n", output)
    npm_output = re.fullmatch(
        rf"\n?> api-gateway-core@1\.2\.0 benchmark\r?\n"
        rf"> node benchmark\.js\r?\n\r?\n"
        rf"Elapsed: {number}s\r?\n",
        output,
    )
    match = script_only or npm_output
    assert match is not None, (
        "benchmark_results.txt must contain exactly the console output from the provided benchmark "
        "command, including a single 'Elapsed: <seconds>s' result and no extra content."
    )
    elapsed = float(match.group(1))
    assert math.isfinite(elapsed) and elapsed >= 0, "Benchmark output contains an invalid elapsed time."


def test_validate_payload_correctness():
    test_script = r'''
    const crypto = require('crypto');
    const addon = require('/app/api-gateway-core/build/Release/validator.node');

    function expectResult(value, expected, label) {
        const actual = addon.validatePayload(value);
        if (actual !== expected) {
            throw new Error(`${label}: expected ${expected}, got ${actual} for ${JSON.stringify(value)}`);
        }
    }

    // Known valid forms, including both alphabet symbols and legal padding.
    for (const value of ['', 'TWFu', 'TWE=', 'TQ==', '+/8=', 'AAAA']) {
        expectResult(value, true, 'valid Base64 rejected');
    }

    // Derive fresh valid inputs from random bytes and invalid inputs by corrupting them.
    for (let i = 0; i < 40; i++) {
        const length = 1 + crypto.randomInt(1, 512);
        const encoded = crypto.randomBytes(length).toString('base64');
        expectResult(encoded, true, 'generated valid Base64 rejected');

        const position = crypto.randomInt(0, encoded.length);
        const corrupted = encoded.slice(0, position) + '%' + encoded.slice(position + 1);
        expectResult(corrupted, false, 'invalid character accepted');
    }

    // Base64 length and padding are structural checks, not merely alphabet checks.
    const malformed = [
        'A', 'AAA', '=AAA', 'A=AA', 'AA=A', 'AAAA=', 'TQ===', '====',
        'AA AA', 'AA\nAA', 'TQ==A'
    ];
    for (const value of malformed) {
        expectResult(value, false, 'malformed Base64 accepted');
    }

    // Derive malformed padding and length cases from valid padded encodings.
    for (const length of [1, 2, 4, 5, 7, 8]) {
        const encoded = crypto.randomBytes(length).toString('base64');
        expectResult(encoded, true, 'generated padded Base64 rejected');
        expectResult('=' + encoded.slice(0, -1), false, 'leading/moved padding accepted');
        expectResult(encoded + '=', false, 'excess padding accepted');
        expectResult(encoded.slice(0, -1), false, 'invalid Base64 length accepted');
    }

    for (const value of [null, 42, true, Buffer.from('AAAA')]) {
        let threw = false;
        try {
            addon.validatePayload(value);
        } catch (_) {
            threw = true;
        }
        if (!threw) throw new Error('non-string input did not throw');
    }
    '''

    result = subprocess.run(
        ["node", "-e", test_script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Base64 correctness checks failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_addon_performance():
    if not os.path.isfile(ADDON):
        pytest.fail("Cannot run performance test because the addon is not compiled.")

    test_script = """
    const addon = require('/app/api-gateway-core/build/Release/validator.node');
    const payload = "A".repeat(100000); // 100KB valid Base64 string

    const start = process.hrtime.bigint();
    for(let i=0; i<1000; i++) {
        const res = addon.validatePayload(payload);
        if (!res) throw new Error("Validation incorrectly failed");
    }
    const end = process.hrtime.bigint();
    const elapsedSec = Number(end - start) / 1e9;
    console.log(elapsedSec);
    """

    try:
        result = subprocess.run(
            ["node", "-e", test_script],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Addon execution failed or validation logic is incorrect. Error: {e.stderr}")

    try:
        time_taken = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Could not parse execution time from output: {result.stdout}")

    threshold = 0.25
    assert time_taken <= threshold, f"Performance threshold not met. Time taken: {time_taken}s (Threshold: {threshold}s). The C++ validation logic is still too slow."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
