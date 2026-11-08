#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import re
import xml.etree.ElementTree as ET
import configparser
import stat
import subprocess
import secrets


def get_expected_data():
    configs_dir = '/home/user/configs'
    expected_rows = []

    for filename in os.listdir(configs_dir):
        filepath = os.path.join(configs_dir, filename)
        if not os.path.isfile(filepath):
            continue

        fmt = filename.split('.')[-1]
        port = None
        memory_str = None

        if fmt == 'json':
            with open(filepath, 'r') as f:
                data = json.load(f)
                port = data['app']['port']
                memory_str = data['app']['memory']
        elif fmt == 'xml':
            tree = ET.parse(filepath)
            root = tree.getroot()
            app = root.find('app')
            port = int(app.find('port').text)
            memory_str = app.find('memory').text
        elif fmt == 'ini':
            config = configparser.ConfigParser()
            config.read(filepath)
            port = int(config['app']['port'])
            memory_str = config['app']['memory']
        else:
            continue

        if memory_str.endswith('M'):
            memory_mb = int(memory_str[:-1])
        elif memory_str.endswith('G'):
            memory_mb = int(memory_str[:-1]) * 1024
        else:
            memory_mb = int(memory_str)

        expected_rows.append([filename, fmt, str(port), str(memory_mb)])

    expected_rows.sort(key=lambda x: x[0])
    return expected_rows


def test_audit_script_exists_and_executable():
    script_path = '/home/user/audit.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_audit_script_runs_on_unseen_inputs():
    configs_dir = '/home/user/configs'
    token = secrets.token_hex(8)
    port1 = 9100 + secrets.randbelow(200)
    port2 = 9300 + secrets.randbelow(200)
    port3 = 9500 + secrets.randbelow(200)
    gigabytes = 3 + secrets.randbelow(6)
    megabytes = 300 + secrets.randbelow(600)

    with open(os.path.join(configs_dir, f'verifier_{token}_a.json'), 'w') as f:
        json.dump({'app': {'port': port1, 'memory': f'{gigabytes}G'}}, f)
        f.write('\n')
    with open(os.path.join(configs_dir, f'verifier_{token}_b.xml'), 'w') as f:
        f.write(f'<config><app><port>{port2}</port><memory>{megabytes}M</memory></app></config>\n')
    with open(os.path.join(configs_dir, f'verifier_{token}_c.ini'), 'w') as f:
        f.write(f'[app]\nport={port3}\nmemory={gigabytes + 1}G\n')

    csv_path = '/home/user/config_audit.csv'
    if os.path.exists(csv_path):
        os.remove(csv_path)

    result = subprocess.run(
        ['/home/user/audit.sh'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'audit.sh exited with status {result.returncode}. '
        f'stdout: {result.stdout} stderr: {result.stderr}'
    )
    assert os.path.isfile(csv_path), 'audit.sh did not generate /home/user/config_audit.csv.'


def test_audit_script_uses_parallelization():
    script_path = '/home/user/audit.sh'
    with open(script_path, 'r') as f:
        content = f.read()

    # Check for common parallelization constructs in bash
    has_parallel = re.search(r'\b(parallel|xargs\s+-P|&)\b', content)
    assert has_parallel, "Script does not seem to implement parallel data processing (missing '&', 'xargs -P', or 'parallel')."


def test_config_audit_csv_correctness():
    csv_path = '/home/user/config_audit.csv'
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    expected_header = ['filename', 'format', 'port', 'memory_mb']
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    expected_data = get_expected_data()

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
