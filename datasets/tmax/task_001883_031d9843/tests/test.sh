#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import json
import os
import re
import subprocess
from pathlib import Path


def normalize_proto(text):
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'\s+', '', text)
    return text.lower()


def test_generator_reads_struct_and_emits_valid_matching_proto():
    generator = Path('/app/generate_proto.py')
    target = Path('/app/sensor.proto')
    trace_file = Path('/tmp/generator_accesses.json')
    runner = Path('/tmp/run_generator_with_audit.py')

    assert generator.is_file(), 'Required generator /app/generate_proto.py does not exist.'
    assert os.access(generator, os.R_OK), 'Generator is not readable.'

    runner.write_text(r'''import json
import runpy
import sys

records = []
state = {'active': True}

def audit(event, args):
    if not state['active']:
        return
    if event == 'open':
        try:
            records.append({'event': event, 'path': str(args[0])})
        except Exception:
            pass
    elif event == 'subprocess.Popen':
        records.append({'event': event, 'args': repr(args)})

sys.addaudithook(audit)
try:
    sys.argv = ['/app/generate_proto.py']
    runpy.run_path('/app/generate_proto.py', run_name='__main__')
finally:
    state['active'] = False
    with open('/tmp/generator_accesses.json', 'w') as f:
        json.dump(records, f)
''')

    target.unlink(missing_ok=True)
    trace_file.unlink(missing_ok=True)
    result = subprocess.run(
        ['python3', str(runner)],
        cwd='/app',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'generate_proto.py failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert target.is_file(), 'Running generate_proto.py did not create /app/sensor.proto.'
    assert trace_file.is_file(), 'Could not verify generator input accesses.'

    records = json.loads(trace_file.read_text())
    consumed_struct = False
    for record in records:
        if record.get('event') == 'subprocess.Popen':
            command = record.get('args', '')
            if 'struct.png' in command:
                consumed_struct = True
                break
            continue

        raw_path = record.get('path', '')
        path = Path(raw_path)
        if not path.is_absolute():
            path = Path('/app') / path
        try:
            resolved = path.resolve()
        except OSError:
            continue

        if resolved == Path('/app/struct.png'):
            consumed_struct = True
            break
        if resolved in (generator, target) or not resolved.is_file():
            continue
        try:
            source_text = resolved.read_text(errors='ignore')
        except OSError:
            continue
        required_tokens = ('SensorData', 'sensor_id', 'temperature', 'timestamp', 'status')
        if all(token in source_text for token in required_tokens):
            consumed_struct = True
            break

    assert consumed_struct, (
        'generate_proto.py did not read /app/struct.png or an extracted C-struct text input.'
    )

    actual_proto = target.read_text()
    without_comments = re.sub(r'//.*', '', actual_proto)
    without_comments = re.sub(r'/\*.*?\*/', '', without_comments, flags=re.S)

    schema_pattern = re.compile(
        r'^\s*syntax\s*=\s*["\']proto3["\']\s*;\s*'
        r'message\s+SensorData\s*\{\s*'
        r'int32\s+sensor_id\s*=\s*1\s*;\s*'
        r'float\s+temperature\s*=\s*2\s*;\s*'
        r'double\s+timestamp\s*=\s*3\s*;\s*'
        r'string\s+status\s*=\s*4\s*;\s*'
        r'\}\s*$',
        re.S,
    )
    assert schema_pattern.fullmatch(without_comments), (
        'Generated sensor.proto is not the required valid proto3 schema. '
        f'Actual content: {actual_proto!r}'
    )

    expected_proto = '''
syntax="proto3";
message SensorData {
    int32 sensor_id = 1;
    float temperature = 2;
    double timestamp = 3;
    string status = 4;
}
'''
    expected_norm = normalize_proto(expected_proto)
    actual_norm = normalize_proto(actual_proto)
    ratio = difflib.SequenceMatcher(None, expected_norm, actual_norm).ratio()
    threshold = 0.90
    assert ratio >= threshold, (
        f'Similarity ratio {ratio:.4f} is below the threshold of {threshold}. '
        f'Actual normalized: {actual_norm}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
