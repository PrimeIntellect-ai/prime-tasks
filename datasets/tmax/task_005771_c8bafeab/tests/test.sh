#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import tempfile

RECOVERED_PATH = '/home/user/recovered_metrics.log'
SCRIPT_PATH = '/home/user/aggregate_uptime.py'
OUTPUT_PATH = '/home/user/total_uptime.json'

EXPECTED_RECOVERED = (
    '{"host": "web-01", "uptime_ms": 5000}\n'
    '{"host": "web-02", "uptime_ms": 7500}\n'
    '{"host": "db-01", "uptime_ms": 12000}\n'
    'FATAL: kernel panic - not syncing\n'
    '{"host": "cache-01", "uptime_ms": NaN}\n'
    '{"host": "web-03", "uptime_ms": 3000}\n'
)


def test_recovered_file_exists_and_is_complete():
    assert os.path.exists(RECOVERED_PATH), f"The recovered log file {RECOVERED_PATH} is missing."
    assert os.path.isfile(RECOVERED_PATH), f"{RECOVERED_PATH} is not a file."

    with open(RECOVERED_PATH, 'r') as f:
        content = f.read()

    # Preserve the original known-line assertion.
    assert '{"host": "web-01", "uptime_ms": 5000}' in content, \
        "The recovered log file does not contain the expected metrics data."
    assert content == EXPECTED_RECOVERED, \
        "The recovered log file is incomplete or does not match the deleted file's full contents."


def test_total_uptime_json():
    assert os.path.exists(OUTPUT_PATH), \
        f"The output file {OUTPUT_PATH} is missing. Did you run the aggregator script?"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {OUTPUT_PATH} does not contain valid JSON."

    assert "total_uptime_ms" in data, f"Key 'total_uptime_ms' is missing in {OUTPUT_PATH}."
    assert data == {"total_uptime_ms": 15500}, \
        f"Expected exactly {{'total_uptime_ms': 15500}}, but got {data!r}."


def test_aggregator_uses_json_parser_and_handles_bad_lines():
    assert os.path.exists(SCRIPT_PATH), f"The aggregator script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        assert False, f"The aggregator script is not valid Python: {exc}"

    module_aliases = set()
    parser_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'json':
                    module_aliases.add(alias.asname or 'json')
        elif isinstance(node, ast.ImportFrom) and node.module == 'json':
            for alias in node.names:
                if alias.name in ('load', 'loads', 'JSONDecoder'):
                    parser_names.add(alias.asname or alias.name)

    uses_json_parser = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in parser_names:
            uses_json_parser = True
        elif isinstance(node.func, ast.Attribute):
            if (isinstance(node.func.value, ast.Name)
                    and node.func.value.id in module_aliases
                    and node.func.attr in ('load', 'loads', 'JSONDecoder')):
                uses_json_parser = True

    assert module_aliases or parser_names, "The aggregator script must import the json module."
    assert uses_json_parser, "The aggregator script must use json to parse log entries."

    values = [1000 + secrets.randbelow(1000) for _ in range(4)]
    expected = sum(values)
    probe = (
        json.dumps({"host": "probe-a", "uptime_ms": values[0]}) + '\n'
        + '{this is malformed JSON}\n'
        + json.dumps({"host": "probe-missing-key"}) + '\n'
        + json.dumps({"host": "probe-b", "uptime_ms": values[1]}) + '\n'
        + '{"host": "probe-nan", "uptime_ms": NaN}\n'
        + json.dumps({"host": "probe-c", "uptime_ms": values[2]}) + '\n'
        + json.dumps({"host": "probe-d", "uptime_ms": values[3]}) + '\n'
    )

    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            original_output = f.read()

    fd, probe_path = tempfile.mkstemp(prefix='uptime_probe_', suffix='.log')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(probe)

        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)

        result = subprocess.run(
            ['python3', SCRIPT_PATH, probe_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, \
            f"The aggregator crashed on malformed or missing-key input:\n{result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), \
            f"Running the aggregator did not create {OUTPUT_PATH}."

        with open(OUTPUT_PATH, 'r') as f:
            try:
                result_data = json.load(f)
            except json.JSONDecodeError as exc:
                assert False, f"The aggregator wrote invalid JSON: {exc}"

        assert result_data == {"total_uptime_ms": expected}, \
            f"The aggregator did not sum valid entries and skip invalid ones; expected {expected}, got {result_data!r}."
    finally:
        try:
            os.unlink(probe_path)
        except FileNotFoundError:
            pass
        if original_output is not None:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(original_output)
        else:
            try:
                os.unlink(OUTPUT_PATH)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
