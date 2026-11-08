#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import stat
import subprocess

import pytest

SCRIPT_PATH = '/home/user/process_artifacts.py'
EXTRACTOR_PATH = '/home/user/build_tools/extractor'
SOURCE_PATH = '/home/user/build_tools/extractor.c'
ARTIFACTS_DIR = '/home/user/artifacts'
JSON_PATH = '/home/user/artifact_metrics.json'


def expected_from_artifacts(overrides=None):
    overrides = overrides or {}
    expected = {}
    for filename in os.listdir(ARTIFACTS_DIR):
        if not filename.endswith('.bin'):
            continue
        if filename in overrides:
            expression = overrides[filename]
        else:
            with open(os.path.join(ARTIFACTS_DIR, filename), 'r') as f:
                content = f.read()
            match = re.search(r'HEX\[(.*?)\]', content)
            assert match is not None, f"Could not find HEX marker in {filename}"
            expression = bytes.fromhex(match.group(1)).decode('ascii')
        expected[filename] = int(eval(expression))
    return expected


def test_process_artifacts_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing"


def test_extractor_compiled_and_executable():
    assert os.path.isfile(EXTRACTOR_PATH), f"{EXTRACTOR_PATH} binary is missing. Did you run make?"
    assert os.access(EXTRACTOR_PATH, os.X_OK), f"{EXTRACTOR_PATH} binary is not executable"


def test_extractor_execution_fixed():
    if not os.path.isfile(EXTRACTOR_PATH):
        pytest.skip("extractor binary not found")

    test_file = '/tmp/test_artifact_long.bin'
    # 60 characters long hex string to test buffer overflow fix (original buffer was 16)
    test_hex = "41" * 60
    with open(test_file, 'w') as f:
        f.write(f"JUNK_HEX[{test_hex}]JUNK")

    result = subprocess.run([EXTRACTOR_PATH, test_file], capture_output=True, text=True)
    assert result.returncode == 0, "extractor crashed or returned non-zero exit code when processing long hex data. Memory safety issue might still exist."
    assert f"ENCODED:{test_hex}" in result.stdout, "extractor did not output the correct ENCODED string for long hex data. Buffer overflow or truncation might still exist."


def test_submitted_source_and_binary_are_memory_safe_on_varied_inputs(tmp_path):
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is missing"
    sanitized = tmp_path / 'extractor_sanitized'
    build = subprocess.run(
        [
            'gcc', '-O1', '-g', '-Wall', '-Wextra',
            '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
            SOURCE_PATH, '-o', str(sanitized),
        ],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"extractor.c does not compile with sanitizers:\n{build.stdout}\n{build.stderr}"

    rng = random.SystemRandom()
    lengths = [1, 15, 16, 17, 31, 60, 127, 511, 2048, rng.randrange(3000, 7000)]
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1:abort_on_error=1'
    env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'

    for index, length in enumerate(lengths):
        payload = ''.join(rng.choice('0123456789abcdefABCDEF') for _ in range(length))
        artifact = tmp_path / f'fuzz_{index}_{secrets.token_hex(4)}.bin'
        artifact.write_text(f"prefix-{secrets.token_hex(12)}-HEX[{payload}]-suffix-{secrets.token_hex(8)}")
        expected = f"ENCODED:{payload}\n"

        production = subprocess.run(
            [EXTRACTOR_PATH, str(artifact)], capture_output=True, text=True, timeout=5
        )
        assert production.returncode == 0, f"compiled extractor failed for a {length}-character payload"
        assert production.stdout == expected, f"compiled extractor returned incorrect data for a {length}-character payload"

        checked = subprocess.run(
            [str(sanitized), str(artifact)], capture_output=True, text=True,
            timeout=5, env=env,
        )
        assert checked.returncode == 0, (
            f"sanitized extractor failed for a {length}-character payload:\n{checked.stderr}"
        )
        assert checked.stdout == expected, f"extractor.c returned incorrect data for a {length}-character payload"
        assert 'AddressSanitizer' not in checked.stderr
        assert 'runtime error:' not in checked.stderr


def test_process_script_executes_extractor_and_handles_runtime_artifacts(tmp_path):
    token = secrets.token_hex(8)
    dynamic = {
        f'runtime_{token}_a.bin': f"({random.randint(20, 80)} + 7) * 3",
        f'runtime_{token}_b.bin': f"{random.randint(100, 180)} - 9 * 4",
    }
    decoy_expression = '1 + 1'
    created = []
    for filename in dynamic:
        path = os.path.join(ARTIFACTS_DIR, filename)
        with open(path, 'w') as f:
            f.write(f"DECOY_HEX[{decoy_expression.encode('ascii').hex()}]END")
        created.append(path)

    original_names = sorted(name for name in os.listdir(ARTIFACTS_DIR) if name.endswith('.bin'))
    expected = expected_from_artifacts(dynamic)
    backup = str(tmp_path / 'real_extractor')
    call_log = str(tmp_path / 'extractor_calls.log')
    os.replace(EXTRACTOR_PATH, backup)

    wrapper_lines = [
        '#!/bin/sh',
        f"printf '%s\\n' \"$1\" >> '{call_log}'",
        'case "$(basename "$1")" in',
    ]
    for filename, expression in dynamic.items():
        wrapper_lines.extend([
            f"  '{filename}')",
            f"    printf '%s\\n' 'ENCODED:{expression.encode('ascii').hex()}'",
            '    exit 0',
            '    ;;',
        ])
    wrapper_lines.extend(['esac', f"exec '{backup}' \"$@\""])
    with open(EXTRACTOR_PATH, 'w') as f:
        f.write('\n'.join(wrapper_lines) + '\n')
    os.chmod(EXTRACTOR_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
             stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    run_result = None
    produced = None
    calls = []
    try:
        run_result = subprocess.run(
            ['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=20
        )
        if os.path.isfile(JSON_PATH):
            with open(JSON_PATH, 'r') as f:
                produced = json.load(f)
        if os.path.isfile(call_log):
            with open(call_log, 'r') as f:
                calls = [os.path.basename(line.strip()) for line in f if line.strip()]
    finally:
        if os.path.lexists(EXTRACTOR_PATH):
            os.unlink(EXTRACTOR_PATH)
        os.replace(backup, EXTRACTOR_PATH)
        for path in created:
            if os.path.exists(path):
                os.unlink(path)
        # Restore the requested final output for the normal artifact directory.
        subprocess.run(['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=20)

    assert run_result is not None and run_result.returncode == 0, (
        f"process_artifacts.py failed when executed:\n{run_result.stderr if run_result else ''}"
    )
    assert set(original_names).issubset(set(calls)), "process_artifacts.py did not invoke the extractor for every .bin artifact"
    assert produced == expected, "process_artifacts.py did not parse extractor output and evaluate runtime artifact expressions"


def test_artifact_metrics_json_correct():
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is missing"

    with open(JSON_PATH, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not valid JSON")

    artifacts_dir = ARTIFACTS_DIR
    expected_metrics = {}

    for filename in os.listdir(artifacts_dir):
        if filename.endswith('.bin'):
            file_path = os.path.join(artifacts_dir, filename)
            with open(file_path, 'r') as f:
                content = f.read()

            match = re.search(r'HEX\[(.*?)\]', content)
            assert match is not None, f"Could not find HEX marker in {filename}"
            hex_data = match.group(1)

            decoded = bytes.fromhex(hex_data).decode('ascii')
            result = eval(decoded)
            expected_metrics[filename] = int(result)

    assert metrics == expected_metrics, "The /home/user/artifact_metrics.json does not match the expected evaluated metrics."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
