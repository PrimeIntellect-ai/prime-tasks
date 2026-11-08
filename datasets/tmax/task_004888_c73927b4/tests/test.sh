#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import datetime
import json
import os
import secrets
import stat
import subprocess
import urllib.parse

ETL = "/home/user/etl.go"
RAW = "/home/user/data/raw_logs.jsonl"
PROCESSED = "/home/user/data/processed_logs.jsonl"
METRICS = "/home/user/data/metrics.json"

assert os.path.isfile(ETL), f"Required Go program {ETL} is missing."
assert not os.path.islink(ETL), f"{ETL} must be a regular Go source file, not a symlink."
assert stat.S_ISREG(os.stat(ETL).st_mode), f"{ETL} is not a regular file."

original_records = [
    {"timestamp":"2023-10-12T14:30:00+02:00","ip_address":"192.168.1.45","user_email":"alice.smith@example.com","url":"https://api.example.com/v1/users?id=1","response_time_ms":45},
    {"timestamp":"12/Oct/2023:12:30:00 +0000","ip_address":"10.0.0.5","user_email":"bob@work.org","url":"http://internal.net/reports/q3","response_time_ms":150},
    {"timestamp":"2023-10-12T08:30:00-04:00","ip_address":"172.16.254.1","user_email":"charlie.brown@test.io","url":"https://example.com/","response_time_ms":600},
    {"timestamp":"12/Oct/2023:05:30:00 -0700","ip_address":"8.8.8.8","user_email":"admin@sys.local","url":"https://api.example.com/v1/status","response_time_ms":99},
]

def write_input(records):
    os.makedirs(os.path.dirname(RAW), exist_ok=True)
    with open(RAW, "w") as f:
        for record in records:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")


def run_etl(records):
    write_input(records)
    for path in (PROCESSED, METRICS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        ["go", "run", ETL],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"go run {ETL} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_metrics_json():
    metrics_path = METRICS
    assert os.path.isfile(metrics_path), f"Metrics file {metrics_path} is missing."

    with open(metrics_path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse JSON in {metrics_path}: {e}"

    expected_metrics = {
        "total_processed": 4,
        "fast_count": 2,
        "medium_count": 1,
        "slow_count": 1
    }

    for key, expected_val in expected_metrics.items():
        assert key in metrics, f"Missing key '{key}' in metrics.json"
        assert metrics[key] == expected_val, f"Expected {key} to be {expected_val}, got {metrics[key]}"


def test_processed_logs_jsonl():
    processed_path = PROCESSED
    assert os.path.isfile(processed_path), f"Processed logs file {processed_path} is missing."

    with open(processed_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {processed_path}, found {len(lines)}."

    expected_records = [
        {"timestamp":"2023-10-12T12:30:00Z","ip_address":"192.168.1.0","masked_email":"***@example.com","path":"/v1/users","response_time_ms":45,"speed":"fast"},
        {"timestamp":"2023-10-12T12:30:00Z","ip_address":"10.0.0.0","masked_email":"***@work.org","path":"/reports/q3","response_time_ms":150,"speed":"medium"},
        {"timestamp":"2023-10-12T12:30:00Z","ip_address":"172.16.254.0","masked_email":"***@test.io","path":"/","response_time_ms":600,"speed":"slow"},
        {"timestamp":"2023-10-12T12:30:00Z","ip_address":"8.8.8.0","masked_email":"***@sys.local","path":"/v1/status","response_time_ms":99,"speed":"fast"},
    ]

    for i, (line, expected) in enumerate(zip(lines, expected_records)):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as e:
            assert False, f"Failed to parse JSON on line {i+1} of {processed_path}: {e}"

        expected_keys = set(expected.keys())
        record_keys = set(record.keys())
        assert record_keys == expected_keys, f"Line {i+1} has incorrect keys. Expected {expected_keys}, got {record_keys}"

        for key in expected_keys:
            assert record[key] == expected[key], f"Line {i+1} field '{key}' mismatch. Expected {expected[key]}, got {record[key]}"


run_etl(original_records)
test_metrics_json()
test_processed_logs_jsonl()

# Exercise the submitted program on fresh data, including both timestamp formats
# and all speed-category boundaries. Randomized values prevent fixed artifact output.
token = secrets.token_hex(6)
dynamic_records = [
    {"timestamp":"2025-01-02T03:04:05+05:30","ip_address":"11.22.33.47","user_email":f"alpha.{token}@one.example","url":f"https://host.example/a/{token}?q=ignored","response_time_ms":0},
    {"timestamp":"02/Jan/2025:03:04:05 +0000","ip_address":"44.55.66.78","user_email":f"beta-{token}@two.example","url":"http://other.example/root/item?x=1#frag","response_time_ms":99},
    {"timestamp":"2024-06-30T23:59:59-03:00","ip_address":"101.102.103.104","user_email":f"gamma@{token}.example","url":"https://example.net/","response_time_ms":100},
    {"timestamp":"01/Jul/2024:02:59:59 +0000","ip_address":"201.202.203.204","user_email":f"delta@four-{token}.example","url":"http://example.net/deep/path?secret=yes","response_time_ms":500},
    {"timestamp":"2030-12-31T23:00:01+01:00","ip_address":"7.19.31.43","user_email":f"epsilon.long@five-{token}.example","url":f"https://api.example.org/v2/{token}/status","response_time_ms":501},
    {"timestamp":"31/Dec/2030:14:00:01 -0800","ip_address":"88.99.111.222","user_email":f"zeta@ six-{token}.example".replace("@ ", "@"),"url":"http://logs.example.org/final","response_time_ms":777},
]


def expected_record(record):
    raw_ts = record["timestamp"]
    if "/" in raw_ts:
        parsed = datetime.datetime.strptime(raw_ts, "%d/%b/%Y:%H:%M:%S %z")
    else:
        parsed = datetime.datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
    timestamp = parsed.astimezone(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    domain = record["user_email"].split("@", 1)[1]
    response = record["response_time_ms"]
    speed = "fast" if response < 100 else ("medium" if response <= 500 else "slow")
    return {
        "timestamp": timestamp,
        "ip_address": record["ip_address"].rsplit(".", 1)[0] + ".0",
        "masked_email": "***@" + domain,
        "path": urllib.parse.urlparse(record["url"]).path,
        "response_time_ms": response,
        "speed": speed,
    }


run_etl(dynamic_records)
expected_dynamic = [expected_record(record) for record in dynamic_records]
assert os.path.isfile(PROCESSED), f"Processed logs file {PROCESSED} is missing after dynamic run."
with open(PROCESSED) as f:
    dynamic_lines = [line.strip() for line in f if line.strip()]
assert len(dynamic_lines) == len(expected_dynamic), (
    f"Expected {len(expected_dynamic)} dynamically processed lines, got {len(dynamic_lines)}"
)
for index, (line, expected) in enumerate(zip(dynamic_lines, expected_dynamic), 1):
    actual = json.loads(line)
    assert set(actual) == set(expected), f"Dynamic line {index} has incorrect fields: {set(actual)}"
    assert actual == expected, f"Dynamic line {index} mismatch. Expected {expected}, got {actual}"

assert os.path.isfile(METRICS), f"Metrics file {METRICS} is missing after dynamic run."
with open(METRICS) as f:
    actual_metrics = json.load(f)
expected_metrics = {
    "total_processed": len(dynamic_records),
    "fast_count": 2,
    "medium_count": 2,
    "slow_count": 2,
}
assert set(actual_metrics) == set(expected_metrics), f"metrics.json has incorrect fields: {set(actual_metrics)}"
assert all(type(value) is int for value in actual_metrics.values()), "All metric values must be integers."
assert actual_metrics == expected_metrics, f"Dynamic metrics mismatch: expected {expected_metrics}, got {actual_metrics}"
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
