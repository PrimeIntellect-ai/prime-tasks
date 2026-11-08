#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import py_compile
import re
import secrets
import subprocess
import sys
import time
from urllib.parse import urlparse

import pytest


def test_protobuf_compiled():
    pb2_file = "/home/user/request_pb2.py"
    assert os.path.isfile(pb2_file), f"Protobuf bindings not found at {pb2_file}"


def test_protobuf_and_parser_behavior():
    pb2_file = "/home/user/request_pb2.py"
    parser_file = "/home/user/legacy_parser.py"

    spec = importlib.util.spec_from_file_location("request_pb2", pb2_file)
    module = importlib.util.module_from_spec(spec)
    sys.modules["request_pb2"] = module
    spec.loader.exec_module(module)

    assert hasattr(module, "RouteRequest"), "request_pb2.py does not define RouteRequest"
    fields = module.RouteRequest.DESCRIPTOR.fields_by_name
    assert set(fields) == {"url", "domain", "rate_limit"}
    assert fields["url"].number == 1
    assert fields["domain"].number == 2
    assert fields["rate_limit"].number == 3

    token = secrets.token_hex(6)
    test_urls = [
        f"https://api-{token}.example.test/v1/items?q=1",
        f"http://legacy-{token}.internal.test/status",
    ]
    for url in test_urls:
        result = subprocess.run(
            ["python3", parser_file, url], capture_output=True, timeout=10
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        expected = module.RouteRequest()
        expected.url = url
        expected.domain = urlparse(url).netloc
        expected.rate_limit = 10
        assert result.stdout == expected.SerializeToString(), (
            "legacy_parser.py did not emit the expected serialized RouteRequest"
        )


def test_legacy_parser_python3():
    parser_file = "/home/user/legacy_parser.py"
    assert os.path.isfile(parser_file), f"File {parser_file} is missing."

    try:
        py_compile.compile(parser_file, doraise=True)
    except py_compile.PyCompileError as e:
        pytest.fail(f"{parser_file} is not valid Python 3: {e}")

    with open(parser_file, "r") as f:
        content = f.read()

    assert "urllib.parse" in content, f"Expected 'urllib.parse' in {parser_file} for Python 3 compatibility."
    assert "sys.stdout.buffer.write" in content or "sys.stdout.write" in content, \
        f"Expected stdout write method in {parser_file}."
    assert "urlparse" not in content.split(), f"Found Python 2 'urlparse' in {parser_file}."


def test_process_requests_executable():
    script_file = "/home/user/process_requests.sh"
    assert os.path.isfile(script_file), f"Script {script_file} is missing."
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable."


def test_processing_log_content():
    log_file = "/home/user/processing.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_patterns = [
        r"^Domain: api\.example\.com \| URL: https://api\.example\.com/v1/users \| PeakMem: \d+ KB$",
        r"^Domain: legacy\.internal\.net \| URL: http://legacy\.internal\.net/status \| PeakMem: \d+ KB$",
        r"^Domain: grpc\.service\.org \| URL: https://grpc\.service\.org/v2/update \| PeakMem: \d+ KB$"
    ]

    for pattern in expected_patterns:
        found = any(re.match(pattern, line) for line in lines)
        assert found, f"Could not find a line matching pattern '{pattern}' in {log_file}."


def test_script_execution_time():
    script_file = "/home/user/process_requests.sh"
    assert os.path.isfile(script_file), f"Script {script_file} is missing."

    start_time = time.time()
    result = subprocess.run([script_file], capture_output=True, text=True)
    end_time = time.time()

    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    elapsed = end_time - start_time
    assert elapsed >= 3.0, f"Script execution time was {elapsed:.2f}s, expected at least 3.0s due to rate limiting."


def test_pipeline_on_derived_inputs_with_profiling_and_per_request_delay():
    script_file = "/home/user/process_requests.sh"
    urls_file = "/home/user/urls.txt"
    log_file = "/home/user/processing.log"
    time_path = "/usr/bin/time"
    real_time = "/usr/bin/time.verifier-real"
    event_file = "/tmp/time-verifier-events.jsonl"

    token = secrets.token_hex(8)
    urls = [
        f"https://one-{token}.example.test/a",
        f"http://two-{token}.internal.test/b?x=1",
        f"https://three-{token}.service.test/c/d",
    ]

    saved_urls = open(urls_file, "rb").read()
    saved_log = open(log_file, "rb").read() if os.path.exists(log_file) else None
    time_mode = os.stat(time_path).st_mode

    wrapper = r'''#!/usr/bin/python3
import json
import os
import re
import subprocess
import sys
import time

event_file = "/tmp/time-verifier-events.jsonl"
with open(event_file, "a", encoding="utf-8") as f:
    index = sum(1 for _ in open(event_file, "r", encoding="utf-8"))
    event = {"timestamp": time.time(), "argv": sys.argv[1:], "peak": 73001 + index}
    f.write(json.dumps(event) + "\n")

result = subprocess.run(["/usr/bin/time.verifier-real"] + sys.argv[1:], stderr=subprocess.PIPE)
stderr = result.stderr.decode("utf-8", errors="replace")
stderr, count = re.subn(
    r"(Maximum resident set size \(kbytes\):\s*)\d+",
    lambda m: m.group(1) + str(event["peak"]),
    stderr,
)
if count == 0:
    stderr += "\nMaximum resident set size (kbytes): " + str(event["peak"]) + "\n"
sys.stderr.write(stderr)
sys.exit(result.returncode)
'''

    try:
        assert not os.path.exists(real_time), f"Unexpected file already exists: {real_time}"
        with open(urls_file, "w", encoding="utf-8") as f:
            f.write("\n".join(urls) + "\n")
        open(log_file, "w").close()
        if os.path.exists(event_file):
            os.unlink(event_file)

        os.replace(time_path, real_time)
        with open(time_path, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(time_path, 0o755)

        started = time.time()
        result = subprocess.run([script_file], capture_output=True, timeout=15)
        finished = time.time()
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        assert os.path.isfile(event_file), "The script did not invoke /usr/bin/time"
        with open(event_file, encoding="utf-8") as f:
            events = [json.loads(line) for line in f if line.strip()]
        assert len(events) == 3, f"Expected one /usr/bin/time invocation per URL, got {len(events)}"

        for event, url in zip(events, urls):
            argv = event["argv"]
            assert len(argv) == 4, f"Unexpected /usr/bin/time arguments: {argv!r}"
            assert argv[0] == "-v", f"/usr/bin/time was not invoked with -v: {argv!r}"
            assert os.path.basename(argv[1]) == "python3", f"Parser was not run with python3: {argv!r}"
            assert os.path.realpath(argv[2]) == "/home/user/legacy_parser.py", argv
            assert argv[3] == url, f"URL was not passed as the parser's first argument: {argv!r}"

        delays = [events[0]["timestamp"] - started]
        delays.extend(
            events[i]["timestamp"] - events[i - 1]["timestamp"]
            for i in range(1, len(events))
        )
        for i, delay in enumerate(delays, 1):
            assert 0.90 <= delay <= 1.75, (
                f"URL {i} was not preceded by its own one-second pause; observed {delay:.3f}s"
            )
        assert finished - started >= 3.0

        with open(log_file, encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 3, f"Expected exactly one fresh log line per URL, got {lines!r}"

        pattern = re.compile(r"^Domain: (.+) \| URL: (.+) \| PeakMem: (\d+) KB$")
        for line, url, event in zip(lines, urls, events):
            match = pattern.fullmatch(line)
            assert match, f"Incorrect log format: {line!r}"
            assert match.group(1) == urlparse(url).netloc
            assert match.group(2) == url
            assert int(match.group(3)) == event["peak"], (
                "PeakMem was not extracted from the Maximum resident set size output"
            )
    finally:
        if os.path.exists(time_path) and os.path.exists(real_time):
            os.unlink(time_path)
            os.replace(real_time, time_path)
            os.chmod(time_path, time_mode)
        with open(urls_file, "wb") as f:
            f.write(saved_urls)
        if saved_log is None:
            if os.path.exists(log_file):
                os.unlink(log_file)
        else:
            with open(log_file, "wb") as f:
                f.write(saved_log)
        if os.path.exists(event_file):
            os.unlink(event_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
