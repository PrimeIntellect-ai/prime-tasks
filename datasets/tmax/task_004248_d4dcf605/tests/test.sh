#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_etl_pipeline.py
import json
import math
import os
import re
import secrets
import stat
import subprocess
from datetime import datetime

import pytest

HOME = "/home/user"
RAW = f"{HOME}/raw_server.log"
EXTRACTED = f"{HOME}/extracted.csv"
AGGREGATED = f"{HOME}/aggregated.csv"
FINAL = f"{HOME}/final_metrics.json"
GENERATED = [EXTRACTED, AGGREGATED, FINAL]
SCRIPTS = ["extract.sh", "transform.sh", "load.sh"]
TRACE = "/tmp/etl_pipeline_trace"


def run(command, check=True):
    result = subprocess.run(command, cwd=HOME, capture_output=True, text=True)
    if check and result.returncode != 0:
        pytest.fail(
            f"Command {command!r} failed with exit code {result.returncode}:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def expected_from_log(path):
    endpoint_pattern = re.compile(r"^/api/v[1-3]/[a-z_]+$")
    log_pattern = re.compile(r"\[(.*?)\] .*?endpoint=(\S+) latency_ms=(\d+)")
    extracted = []
    buckets = {}

    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = log_pattern.search(line)
            if not match:
                continue
            timestamp, endpoint, latency_text = match.groups()
            if not endpoint_pattern.fullmatch(endpoint):
                continue
            try:
                dt = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
            except ValueError:
                continue

            latency = int(latency_text)
            extracted.append(f"{timestamp},{endpoint},{latency}")
            bucket = dt.replace(minute=(dt.minute // 5) * 5, second=0).strftime(
                "%Y-%m-%d %H:%M:%S"
            )
            key = (bucket, endpoint)
            data = buckets.setdefault(key, [0, 0])
            data[0] += 1
            data[1] += latency

    aggregated = {
        (bucket, endpoint): (count, math.floor(total / count))
        for (bucket, endpoint), (count, total) in buckets.items()
    }
    final = [
        {
            "bucket": bucket,
            "endpoint": endpoint,
            "request_count": count,
            "avg_latency": average,
        }
        for (bucket, endpoint), (count, average) in aggregated.items()
    ]
    final.sort(key=lambda item: (item["bucket"], item["endpoint"]))
    return extracted, aggregated, final


def assert_extracted(expected):
    assert os.path.isfile(EXTRACTED), "extract.sh did not create extracted.csv"
    with open(EXTRACTED, encoding="utf-8") as handle:
        actual = handle.read().splitlines()
    assert actual == expected, f"Incorrect extracted.csv:\n{actual!r}"


def assert_aggregated(expected):
    assert os.path.isfile(AGGREGATED), "transform.sh did not create aggregated.csv"
    rows = []
    with open(AGGREGATED, encoding="utf-8") as handle:
        for line_number, line in enumerate(handle.read().splitlines(), 1):
            fields = line.split(",")
            assert len(fields) == 4, f"Malformed aggregated.csv line {line_number}: {line!r}"
            bucket, endpoint, count, average = fields
            try:
                rows.append((bucket, endpoint, int(count), int(average)))
            except ValueError:
                pytest.fail(f"Non-integer aggregate on line {line_number}: {line!r}")

    assert [row[0] for row in rows] == sorted(row[0] for row in rows), \
        "aggregated.csv is not sorted chronologically"
    actual = {}
    for bucket, endpoint, count, average in rows:
        key = (bucket, endpoint)
        assert key not in actual, f"Duplicate aggregate group: {key!r}"
        actual[key] = (count, average)
    assert actual == expected, f"Incorrect aggregated.csv:\n{actual!r}"


def assert_final(expected):
    assert os.path.isfile(FINAL), "final_metrics.json was not generated"
    try:
        with open(FINAL, encoding="utf-8") as handle:
            actual = json.load(handle)
    except json.JSONDecodeError as error:
        pytest.fail(f"final_metrics.json is not valid JSON: {error}")

    assert isinstance(actual, list), "The JSON output should be a list of objects"
    try:
        actual.sort(key=lambda item: (item["bucket"], item["endpoint"]))
    except (KeyError, TypeError) as error:
        pytest.fail(f"Malformed JSON records: {error}")

    assert len(actual) == len(expected), \
        f"Expected {len(expected)} JSON records, found {len(actual)}"
    for observed, wanted in zip(actual, expected):
        for key in ("bucket", "endpoint", "request_count", "avg_latency"):
            assert key in observed, f"Missing expected key {key!r}"
            assert observed[key] == wanted[key], \
                f"Expected {key}={wanted[key]!r}, got {observed[key]!r}"


def clean_generated_manually():
    for path in GENERATED:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def read_trace():
    if not os.path.exists(TRACE):
        return []
    with open(TRACE, encoding="utf-8") as handle:
        return handle.read().splitlines()


def assert_order(trace, names):
    position = -1
    for name in names:
        try:
            position = trace.index(name, position + 1)
        except ValueError:
            pytest.fail(f"Expected script execution order {names!r}, got trace {trace!r}")


def test_complete_etl_pipeline_and_make_dag():
    assert os.path.isfile(f"{HOME}/Makefile"), "Makefile is missing in /home/user"

    originals = {}
    for script_name in SCRIPTS:
        path = f"{HOME}/{script_name}"
        assert os.path.isfile(path), f"{script_name} is missing"
        mode = os.stat(path).st_mode
        assert stat.S_ISREG(mode), f"{script_name} is not a regular file"
        assert os.access(path, os.X_OK), f"{script_name} is not executable"
        with open(path, "rb") as handle:
            content = handle.read()
        assert content.startswith(b"#!") and b"bash" in content.splitlines()[0], \
            f"{script_name} must be a Bash script"
        originals[path] = (content, mode)

    extract_text = originals[f"{HOME}/extract.sh"][0].decode("utf-8", errors="replace")
    assert re.search(r"=~|\b(?:grep|egrep|sed|awk|gawk)\b", extract_text), \
        "extract.sh does not appear to use a regular expression"

    nonce = secrets.randbelow(700) + 101
    lines = [
        f"[2024-02-29 23:58:59] srcIP=192.0.2.1 method=GET endpoint=/api/v1/alpha latency_ms={nonce}",
        f"[2024-02-29 23:59:59] srcIP=192.0.2.2 method=POST endpoint=/api/v1/alpha latency_ms={nonce + 7}",
        f"[2024-03-01 00:00:00] srcIP=192.0.2.3 method=GET endpoint=/api/v3/data_export latency_ms={nonce + 19}",
        f"[2024-03-01 00:04:59] srcIP=192.0.2.4 method=GET endpoint=/api/v3/data_export latency_ms={nonce + 24}",
        f"[2024-03-01 00:05:00] srcIP=192.0.2.5 method=POST endpoint=/api/v2/z latency_ms={nonce + 41}",
        f"[2024-03-01 00:01:00] srcIP=192.0.2.6 method=GET endpoint=/api/v4/admin latency_ms={nonce + 1}",
        f"[2024-03-01 00:01:01] srcIP=192.0.2.6 method=GET endpoint=/api/v0/admin latency_ms={nonce + 2}",
        f"[2024-03-01 00:01:02] srcIP=192.0.2.6 method=GET endpoint=/api/v12/admin latency_ms={nonce + 3}",
        f"[2024-03-01 00:01:03] srcIP=192.0.2.6 method=GET endpoint=/api/v2/UPPER latency_ms={nonce + 4}",
        f"[2024-03-01 00:01:04] srcIP=192.0.2.6 method=GET endpoint=/api/v2/user2 latency_ms={nonce + 5}",
        f"[2024-03-01 00:01:05] srcIP=192.0.2.6 method=GET endpoint=/api/v2/two/parts latency_ms={nonce + 6}",
        f"[2024-03-01 00:01:06] srcIP=192.0.2.6 method=GET endpoint=/health latency_ms={nonce + 7}",
        "this is not a server log line",
    ]
    with open(RAW, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    expected_extracted, expected_aggregated, expected_final = expected_from_log(RAW)

    # Execute and validate each submitted script directly.
    clean_generated_manually()
    run([f"{HOME}/extract.sh"])
    assert_extracted(expected_extracted)
    run([f"{HOME}/transform.sh"])
    assert_aggregated(expected_aggregated)
    run([f"{HOME}/load.sh"])
    assert_final(expected_final)

    # Instrument the submitted scripts so Makefile targets must actually execute them.
    try:
        for path, (content, mode) in originals.items():
            first_newline = content.find(b"\n")
            assert first_newline >= 0, f"Invalid script file: {path}"
            name = os.path.basename(path)
            marker = f"printf '%s\\n' '{name}' >> {TRACE}\n".encode()
            instrumented = content[:first_newline + 1] + marker + content[first_newline + 1:]
            with open(path, "wb") as handle:
                handle.write(instrumented)
            os.chmod(path, stat.S_IMODE(mode))

        clean_result = run(["make", "clean"])
        assert clean_result.returncode == 0
        assert all(not os.path.exists(path) for path in GENERATED), \
            "make clean did not remove all generated CSV and JSON files"

        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
        run(["make", "extract"])
        assert_extracted(expected_extracted)
        assert not os.path.exists(AGGREGATED) and not os.path.exists(FINAL), \
            "make extract incorrectly generated downstream outputs"
        assert "extract.sh" in read_trace(), "make extract did not execute extract.sh"

        run(["make", "clean"])
        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
        run(["make", "transform"])
        assert_extracted(expected_extracted)
        assert_aggregated(expected_aggregated)
        assert not os.path.exists(FINAL), "make transform incorrectly generated final_metrics.json"
        assert_order(read_trace(), ["extract.sh", "transform.sh"])

        run(["make", "clean"])
        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
        run(["make", "load"])
        assert_extracted(expected_extracted)
        assert_aggregated(expected_aggregated)
        assert_final(expected_final)
        assert_order(read_trace(), ["extract.sh", "transform.sh", "load.sh"])

        run(["make", "clean"])
        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
        run(["make", "all"])
        assert_extracted(expected_extracted)
        assert_aggregated(expected_aggregated)
        assert_final(expected_final)
        assert_order(read_trace(), ["extract.sh", "transform.sh", "load.sh"])

        # Change the source after a successful build and require make all to refresh it.
        extra_latency = nonce + 63
        with open(RAW, "a", encoding="utf-8") as handle:
            handle.write(
                f"[2024-03-01 00:09:59] srcIP=198.51.100.9 method=GET "
                f"endpoint=/api/v2/z latency_ms={extra_latency}\n"
            )
        future = max(os.path.getmtime(RAW), os.path.getmtime(FINAL)) + 2
        os.utime(RAW, (future, future))
        expected_extracted, expected_aggregated, expected_final = expected_from_log(RAW)
        run(["make", "all"])
        assert_extracted(expected_extracted)
        assert_aggregated(expected_aggregated)
        assert_final(expected_final)
    finally:
        for path, (content, mode) in originals.items():
            with open(path, "wb") as handle:
                handle.write(content)
            os.chmod(path, stat.S_IMODE(mode))
        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_etl_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
