#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'EOF' > /tmp/original_config_changes.jsonl
{"id": "evt_05", "ts": 1700000045, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_02", "ts": 1700000010, "module": "db", "key": "timeout", "value": "30"}
{"id": "evt_01", "ts": 1700000000, "module": "ui", "key": "greeting", "value": "Hello"}
{"id": "evt_08", "ts": 1700000110, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_04", "ts": 1700000030, "module": "auth", "key": "method", "value": "oauth2"}
{"id": "evt_03", "ts": 1700000010, "module": "db", "key": "timeout", "value": "30"}
{"id": "evt_07", "ts": 1700000080, "module": "auth", "key": "method", "value": "saml"}
{"id": "evt_06", "ts": 1700000045, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_09", "ts": 1700000115, "module": "db", "key": "timeout", "value": "60"}
{"id": "evt_10", "ts": 1700000120, "module": "db", "key": "timeout", "value": "60"}
EOF

python3 - << 'PY'
import json, secrets, time
s = secrets.token_hex(12)
b = int(time.time()) + secrets.randbelow(10000)
events = [
    {"id": "case_09_"+s, "ts": b+95, "module": "ui", "key": "text", "value": "変更-"+s+"-🌍"},
    {"id": "case_02_"+s, "ts": b+10, "module": "db", "key": "limit", "value": "30-"+s},
    {"id": "case_01_"+s, "ts": b, "module": "ui", "key": "text", "value": "line\\n-"+s},
    {"id": "case_03_"+s, "ts": b+10, "module": "db", "key": "limit", "value": "30-"+s},
    {"id": "case_05_"+s, "ts": b+30, "module": "ui", "key": "text", "value": "変更-"+s+"-🌍"},
    {"id": "case_04_"+s, "ts": b+20, "module": "ui", "key": "text", "value": "line\\n-"+s},
    {"id": "case_10_"+s, "ts": b+96, "module": "ui", "key": "text", "value": "line\\n-"+s},
    {"id": "case_11_"+s, "ts": b+100, "module": "auth", "key": "label", "value": "مرحبا-"+s},
    {"id": "case_12_"+s, "ts": b+161, "module": "auth", "key": "label", "value": "こんにちは-"+s},
]
with open('/tmp/random_config_changes.jsonl', 'w', encoding='utf-8') as f:
    for event in events:
        f.write(json.dumps(event, ensure_ascii=True) + '\n')
PY

cat << 'PY' > /tmp/check_outputs.py
import json
import os
import sys

trusted_input = sys.argv[1]
live_input = '/home/user/config_changes.jsonl'

with open(trusted_input, 'rb') as f:
    trusted_bytes = f.read()
with open(live_input, 'rb') as f:
    live_bytes = f.read()
assert live_bytes == trusted_bytes, 'The processor modified or replaced its input file.'

def get_expected_outputs(input_file):
    events = []
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    events.sort(key=lambda x: (x['ts'], x['id']))
    last_accepted = {}
    valid_events = []
    expected_log = []
    expected_stats = []
    for event in events:
        evt_id = event['id']
        ts = event['ts']
        module = event['module']
        key = event['key']
        value = event['value']
        state_key = (module, key)
        if state_key in last_accepted and last_accepted[state_key] == value:
            expected_log.append(f'DUPLICATE: {evt_id}')
        else:
            last_accepted[state_key] = value
            expected_log.append(f'VALID: {evt_id} - {module} - {len(value.encode("utf-8"))}')
            valid_events.append((evt_id, ts))
            rolling_count = sum(1 for _, v_ts in valid_events if ts - 60 <= v_ts <= ts)
            expected_stats.append(f'{evt_id},{rolling_count}')
    return expected_log, expected_stats

expected_log, expected_stats = get_expected_outputs(trusted_input)
log_file = '/home/user/pipeline.log'
stats_file = '/home/user/stats.csv'
assert os.path.isfile(log_file), f'Output file {log_file} is missing.'
assert os.path.isfile(stats_file), f'Output file {stats_file} is missing.'
with open(log_file, 'r', encoding='utf-8') as f:
    actual_log = [line.strip() for line in f if line.strip()]
with open(stats_file, 'r', encoding='utf-8') as f:
    actual_stats = [line.strip() for line in f if line.strip()]
assert actual_log == expected_log, f'Contents of {log_file} do not match the expected output.'
assert actual_stats == expected_stats, f'Contents of {stats_file} do not match the expected output.'
PY

run_case() {
    local executable="$1"
    local input="$2"
    cp "$input" /home/user/config_changes.jsonl || return 1
    rm -f /home/user/pipeline.log /home/user/stats.csv
    (cd /home/user && timeout 20 "$executable") || return 1
    python3 /tmp/check_outputs.py "$input" || return 1
}

run_checks() {
    test -f /home/user/config_processor.cpp || return 1
    test -s /home/user/config_processor.cpp || return 1
    test -f /home/user/config_processor || return 1
    test -x /home/user/config_processor || return 1
    test ! -L /home/user/config_processor || return 1

    python3 - << 'PY' || return 1
import re
source_path = '/home/user/config_processor.cpp'
binary_path = '/home/user/config_processor'
with open(source_path, 'r', encoding='utf-8') as f:
    source = f.read()
source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
source = re.sub(r'//.*?$', '', source, flags=re.M)
assert re.search(r'\bstd\s*::\s*hash\s*<', source), 'Source does not use std::hash.'
with open(binary_path, 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'Compiled binary is not an ELF executable.'
PY

    timeout 30 g++ -std=c++17 -O2 /home/user/config_processor.cpp -o /tmp/config_processor_rebuilt || return 1
    test -x /tmp/config_processor_rebuilt || return 1

    run_case /home/user/config_processor /tmp/original_config_changes.jsonl || return 1
    run_case /home/user/config_processor /tmp/random_config_changes.jsonl || return 1
    run_case /tmp/config_processor_rebuilt /tmp/random_config_changes.jsonl || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
