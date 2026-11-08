#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
INI = HOME / 'config_tracker.ini'
OUTPUT = HOME / 'final_configs.json'
EXCLUDED = {
    INI.resolve(),
    OUTPUT.resolve(),
    (HOME / 'logs/dev_a.xml').resolve(),
    (HOME / 'logs/dev_b.csv').resolve(),
    (HOME / 'logs/dev_c.json').resolve(),
}

original_expected = {
    'device_alpha': {
        'network_speed': '10000',
        'duplex': 'full',
        'mtu': '1500',
    },
    'device_beta': {
        'timeout': '60',
        'retries': '3',
        'mode': 'active',
    },
    'device_gamma': {
        'power_limit': '200W',
        'fan_curve': 'aggressive',
        'led_mode': 'breathing',
    },
}

def str_dict(value):
    if isinstance(value, dict):
        return {k: str_dict(v) for k, v in value.items()}
    return str(value)

def read_result(expected):
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist.'
    with OUTPUT.open('r', encoding='utf-8') as f:
        result = json.load(f)
    assert str_dict(result) == str_dict(expected), (
        'Output JSON does not match the expected consolidated state. '
        'Ensure you are extracting the latest values based on timestamps.'
    )

def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix in ('.sh', '.bash'):
        return ['bash', str(path)]
    try:
        first = path.open('rb').readline(512)
    except OSError:
        return None
    if first.startswith(b'#!'):
        try:
            interpreter = shlex.split(first[2:].decode('utf-8', 'strict').strip())
        except Exception:
            return None
        return interpreter + [str(path)] if interpreter else None
    if os.access(path, os.X_OK):
        return [str(path)]
    return None

def candidates():
    found = []
    for path in HOME.rglob('*'):
        try:
            resolved = path.resolve()
            if not path.is_file() or resolved in EXCLUDED:
                continue
            rel = path.relative_to(HOME)
            if any(part.startswith('.') for part in rel.parts):
                continue
            if rel.parts and rel.parts[0] == 'logs':
                continue
            cmd = command_for(path)
            if cmd is not None:
                found.append((path.stat().st_mtime_ns, len(rel.parts), str(path), cmd))
        except (OSError, ValueError):
            continue
    found.sort(key=lambda x: (-x[0], x[1], x[2]))
    return [item[3] for item in found[:100]]

original_ini = INI.read_bytes()
commands = candidates()
assert commands, 'No runnable script was found under /home/user.'

tmpdir = Path(tempfile.mkdtemp(prefix='config_verifier_'))
token = secrets.token_hex(10)
xml_path = tmpdir / f'{token}_legacy.xml'
csv_path = tmpdir / f'{token}_modern.csv'
json_path = tmpdir / f'{token}_device.json'

xml_param = f'line_speed_{token}'
xml_other = f'label_{token}'
csv_param = f'timeout_{token}'
csv_other = f'retries_{token}'
json_param = f'power_{token}'
json_other = f'mode_{token}'
section_xml = f'legacy_{token}'
section_csv = f'csv_{token}'
section_json = f'json_{token}'

xml_text = f'''<?xml version="1.0" encoding="ISO-8859-1"?>
<log>
  <update><param>{xml_param}</param><value>old</value><time>900</time></update>
  <update><param>{xml_other}</param><value>café</value><time>-4</time></update>
  <update><param>{xml_param}</param><value>new_{token}</value><time>1100</time></update>
</log>
'''
xml_path.write_bytes(xml_text.encode('iso-8859-1'))

csv_text = f'''parameter,value,timestamp
{csv_param},old,9
{csv_other},keep_{token},30
{csv_param},new_{token},100
{csv_other},stale,12
'''
csv_path.write_bytes(csv_text.encode('utf-16le'))

json_data = [
    {'p': json_param, 'v': 'old', 't': 41},
    {'p': json_other, 'v': f'naïve_{token}', 't': -20},
    {'p': json_param, 'v': f'new_{token}', 't': 105},
]
json_path.write_text(json.dumps(json_data, ensure_ascii=False), encoding='utf-8')

dynamic_ini = f'''[{section_xml}]
path = {xml_path}
format = xml
encoding = iso-8859-1

[{section_csv}]
path = {csv_path}
format = csv
encoding = utf-16le

[{section_json}]
path = {json_path}
format = json
encoding = utf-8
'''.encode('utf-8')

dynamic_expected = {
    section_xml: {xml_param: f'new_{token}', xml_other: 'café'},
    section_csv: {csv_param: f'new_{token}', csv_other: f'keep_{token}'},
    section_json: {json_param: f'new_{token}', json_other: f'naïve_{token}'},
}

errors = []
passed = False
try:
    for cmd in commands:
        try:
            INI.write_bytes(original_ini)
            OUTPUT.unlink(missing_ok=True)
            first = subprocess.run(
                cmd, cwd=str(HOME), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=15, check=False,
            )
            if first.returncode != 0:
                raise AssertionError(f'original-fixture exit status {first.returncode}')
            read_result(original_expected)

            INI.write_bytes(dynamic_ini)
            OUTPUT.unlink(missing_ok=True)
            second = subprocess.run(
                cmd, cwd=str(HOME), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=15, check=False,
            )
            if second.returncode != 0:
                raise AssertionError(f'dynamic-fixture exit status {second.returncode}')
            read_result(dynamic_expected)
            passed = True
            break
        except Exception as exc:
            errors.append(f'{cmd!r}: {exc}')
finally:
    INI.write_bytes(original_ini)
    shutil.rmtree(tmpdir, ignore_errors=True)

assert passed, 'No submitted script passed both fixtures. ' + ' | '.join(errors[-5:])
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
