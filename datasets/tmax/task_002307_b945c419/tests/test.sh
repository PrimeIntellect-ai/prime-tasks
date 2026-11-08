#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_normalized_configs_exists_and_valid():
    file_path = '/home/user/normalized_configs.json'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {file_path} does not contain valid JSON."

    assert isinstance(data, list), f"The data in {file_path} must be a JSON array."
    assert len(data) == 3, f"Expected 3 records in {file_path}, found {len(data)}."

    expected_data = [
        {"server": "srv-01", "timestamp": "2023-10-01T14:00:00Z", "key": "max_conns", "value": "100"},
        {"server": "srv-02", "timestamp": "2023-10-01T14:05:00Z", "key": "timeout", "value": "30s"},
        {"server": "srv-03", "timestamp": "2023-10-02T10:00:00Z", "key": "retries", "value": "3"}
    ]

    assert data == expected_data, f"The data in {file_path} does not match the expected normalized, deduplicated, and sorted output."

def test_pipeline_log_exists_and_valid():
    log_path = '/home/user/pipeline.log'
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    with open(log_path, 'r') as f:
        log_contents = f.read().strip()

    expected_log = "[INFO] Processed 6 raw records. Exported 3 unique records."
    assert expected_log in log_contents, f"The file {log_path} does not contain the expected log message. Found: {log_contents}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_pipeline.py
import csv
import json
import os
import secrets
import shutil
import subprocess

script = '/home/user/process_configs.py'
raw_dir = '/home/user/raw_configs'
output_path = '/home/user/normalized_configs.json'
log_path = '/home/user/pipeline.log'

assert os.path.isfile(script), f"The required script {script} does not exist or is not a regular file."
assert not os.path.islink(script), f"The required script {script} must be an actual file, not a symbolic link."

token = secrets.token_hex(8)
server_a = f"dynamic-a-{token}"
server_b = f"dynamic-b-{token}"
server_c = f"dynamic-c-{token}"
common_key = f"common-{token}"
numeric_value = secrets.randbelow(900000) + 100000

shutil.rmtree(raw_dir)
os.makedirs(raw_dir)

json_records = [
    {"host_name": server_b, "event_time": "2041/06/07 08:09:10", "cfg_key": common_key, "cfg_val": numeric_value},
    {"host_name": server_b, "event_time": "2041-06-07T08:09:10Z", "cfg_key": common_key, "cfg_val": str(numeric_value)},
    {"host_name": server_a, "event_time": "2041-06-07T08:09:10Z", "cfg_key": f"zeta-{token}", "cfg_val": f"z-{token}"},
    {"host_name": server_c, "event_time": "2042/01/02 03:04:05", "cfg_key": f"later-{token}", "cfg_val": 7},
]
with open(os.path.join(raw_dir, f"input-{secrets.token_hex(4)}.json"), 'w') as f:
    json.dump(json_records, f)

with open(os.path.join(raw_dir, f"input-{secrets.token_hex(4)}.csv"), 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['server', 'date', 'key', 'value'])
    writer.writeheader()
    writer.writerow({"server": server_b, "date": "2041-06-07T08:09:10Z", "key": common_key, "value": str(numeric_value)})
    writer.writerow({"server": server_c, "date": "2040/01/02 03:04:05", "key": f"early-{token}", "value": f"e-{token}"})
    writer.writerow({"server": server_a, "date": "2041/06/07 08:09:10", "key": f"alpha-{token}", "value": f"a-{token}"})

if os.path.lexists(output_path):
    if os.path.isdir(output_path) and not os.path.islink(output_path):
        shutil.rmtree(output_path)
    else:
        os.unlink(output_path)
with open(log_path, 'w') as f:
    f.write('VERIFIER_SENTINEL\n')

result = subprocess.run(
    ['python3', script],
    cwd='/home/user',
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=20,
)
assert result.returncode == 0, f"process_configs.py failed with exit code {result.returncode}. stdout={result.stdout!r} stderr={result.stderr!r}"
assert os.path.isfile(output_path), "Running process_configs.py did not create normalized_configs.json."

with open(output_path) as f:
    actual = json.load(f)

expected = [
    {"server": server_c, "timestamp": "2040-01-02T03:04:05Z", "key": f"early-{token}", "value": f"e-{token}"},
    {"server": server_a, "timestamp": "2041-06-07T08:09:10Z", "key": f"alpha-{token}", "value": f"a-{token}"},
    {"server": server_a, "timestamp": "2041-06-07T08:09:10Z", "key": f"zeta-{token}", "value": f"z-{token}"},
    {"server": server_b, "timestamp": "2041-06-07T08:09:10Z", "key": common_key, "value": str(numeric_value)},
    {"server": server_c, "timestamp": "2042-01-02T03:04:05Z", "key": f"later-{token}", "value": "7"},
]
assert actual == expected, f"The script produced incorrect dynamic ETL output. Expected {expected!r}, found {actual!r}."
assert all(set(record.keys()) == {'server', 'timestamp', 'key', 'value'} for record in actual), "Every output record must have exactly the four required keys."

with open(log_path) as f:
    log_contents = f.read()
expected_log = '[INFO] Processed 7 raw records. Exported 5 unique records.'
assert log_contents.startswith('VERIFIER_SENTINEL\n'), "The script did not append to the existing pipeline log."
assert log_contents[len('VERIFIER_SENTINEL\n'):].splitlines() == [expected_log], f"The script did not append the correct dynamic log line. Found: {log_contents!r}"
DYNAMIC_EOF

ok=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_pipeline.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
