#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

EXPECTED_CONTENT = (
    "Test 1: 200\n"
    "Test 2: 200\n"
    "Test 3: 429\n"
    "Test 4: 400\n"
    "Test 5: 200\n"
    "Test 6: 429"
)


def assert_expected_log():
    log_path = Path("/home/user/test_results.log")
    assert log_path.is_file(), f"Log file {log_path} does not exist."
    actual_content = log_path.read_text().strip()
    assert actual_content == EXPECTED_CONTENT, (
        f"Contents of {log_path} do not match the expected output.\n"
        f"Expected:\n{EXPECTED_CONTENT}\nActual:\n{actual_content}"
    )


def test_files_exist():
    """Verify that all required files have been created."""
    required_files = [
        "/home/user/deploy.h",
        "/home/user/deploy.c",
        "/home/user/test_deploy.c",
        "/home/user/run_tests",
        "/home/user/test_results.log",
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file {file_path} is missing."


def test_executable_is_executable():
    """Verify that run_tests is an executable."""
    assert os.access("/home/user/run_tests", os.X_OK), "/home/user/run_tests is not executable."
    with open("/home/user/run_tests", "rb") as f:
        assert f.read(4) == b"\x7fELF", "run_tests is not a compiled ELF executable."


def test_test_results_content():
    """Verify the contents of test_results.log match the expected output exactly."""
    assert_expected_log()


def test_fixture_source_requirements():
    source = Path("/home/user/test_deploy.c").read_text()
    assert re.search(r"#\s*include\s*[<\"][^>\"]*deploy\.h[>\"]", source), \
        "test_deploy.c must include deploy.h"
    assert re.search(r"\bmain\s*\(", source), "test_deploy.c must contain main"
    assert "process_deploy_request" in source, \
        "test_deploy.c must call process_deploy_request"

    requests = [
        "ALPHA1 DEPLOY backend@v1.0.0",
        "ALPHA1 DEPLOY backend@v1.0.1",
        "ALPHA1 DEPLOY backend@v1.0.2",
        "BETA2 BADCMD frontend@v2",
        "BETA2 DEPLOY frontend@v2.1.0",
        "ALPHA1 DEPLOY backend@v1.0.3",
    ]
    positions = [source.find(json.dumps(request)) for request in requests]
    assert all(pos >= 0 for pos in positions), \
        "test_deploy.c must contain all six required request strings"
    assert positions == sorted(positions), \
        "The six required requests must appear in the specified order"


def run_and_check(executable):
    log = Path("/home/user/test_results.log")
    if log.exists():
        log.unlink()
    result = subprocess.run(
        [executable], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_expected_log()


def test_existing_and_rebuilt_fixture_execute():
    # Exercise the artifact supplied by the agent rather than trusting its log.
    run_and_check("/home/user/run_tests")

    # Also prove that the submitted sources compile together and that their fixture
    # generates the required log when freshly built.
    rebuilt = "/tmp/rebuilt_run_tests"
    result = subprocess.run(
        [
            "gcc", "-o", rebuilt,
            "/home/user/deploy.c", "/home/user/test_deploy.c",
        ],
        capture_output=True, text=True, timeout=20,
    )
    assert result.returncode == 0, (
        f"Submitted C sources do not compile:\n{result.stdout}\n{result.stderr}"
    )
    run_and_check(rebuilt)


def test_library_behavior_on_additional_requests():
    rng = random.Random(731942)
    cases = []

    # Multiple independently generated tokens exercise parsing, per-token state,
    # malformed-request handling, and the two-request limit.
    for i in range(12):
        token = f"T{i:02d}" + "".join(rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") for _ in range(5))
        target = "svc" + "".join(rng.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(5))
        version = f"v{rng.randrange(1, 10)}.{rng.randrange(0, 20)}.{rng.randrange(0, 20)}"
        cases.extend([
            f"{token} DEPLOY {target}@{version}",
            f"{token}  DEPLOY {target}@{version}",  # malformed; must not consume quota
            f"{token} DEPLOY {target}@v9.9",
            f"{token} DEPLOY {target}@v10.0",
        ])

    cases.extend([
        "ABCDEFGHIJKLMNOP DEPLOY abcdefghijklmnop@v1.2.3",
        "ABCDEFGHIJKLMNOP DEPLOY abcdefghijklmnop@v2",
        "ABCDEFGHIJKLMNOP DEPLOY abcdefghijklmnop@v3",
        "ABCDEFGHIJKLMNOPQ DEPLOY target@v1",
        "GOOD9 DEPLOY abcdefghijklmnopq@v1",
        "BAD_TOKEN DEPLOY target@v1",
        "GOOD10 deploy target@v1",
        "GOOD11 DEPLOY target-v@v1",
        "GOOD12 DEPLOY targetv1",
        "GOOD13 DEPLOY target@1.2",
        "GOOD14 DEPLOY target@v1x2",
        "GOOD15\tDEPLOY target@v1",
        " GOOD16 DEPLOY target@v1",
        "GOOD17 DEPLOY target@v1 ",
        "GOOD18 DEPLOY target@v1\n",
        "GOOD19 DEPLOY target@v1",
        "GOOD19 DEPLOY target@v2",
        "GOOD19 DEPLOY target@v3",
    ])

    valid_pattern = re.compile(
        r"[A-Za-z0-9]{1,16} DEPLOY [A-Za-z0-9]{1,16}@v[0-9.]+\Z",
        re.ASCII,
    )
    counts = {}
    expected = []
    for request in cases:
        if not valid_pattern.fullmatch(request):
            expected.append(400)
            continue
        token = request.split(" ", 1)[0]
        if counts.get(token, 0) >= 2:
            expected.append(429)
        else:
            counts[token] = counts.get(token, 0) + 1
            expected.append(200)

    entries = ",\n".join(
        "    {%s, %d}" % (json.dumps(request), answer)
        for request, answer in zip(cases, expected)
    )
    harness = f'''#include <stdio.h>
#include "deploy.h"

struct test_case {{ const char *request; int expected; }};

int main(void) {{
    struct test_case cases[] = {{
{entries}
    }};
    size_t count = sizeof(cases) / sizeof(cases[0]);
    for (size_t i = 0; i < count; ++i) {{
        int actual = process_deploy_request(cases[i].request);
        if (actual != cases[i].expected) {{
            fprintf(stderr, "case %zu: expected %d, got %d for [%s]\\n",
                    i, cases[i].expected, actual, cases[i].request);
            return 1;
        }}
    }}
    return 0;
}}
'''
    harness_path = Path("/tmp/deploy_behavior_harness.c")
    harness_path.write_text(harness)
    executable = "/tmp/deploy_behavior_harness"
    result = subprocess.run(
        [
            "gcc", "-std=c11", "-I/home/user",
            "/home/user/deploy.c", str(harness_path), "-o", executable,
        ],
        capture_output=True, text=True, timeout=20,
    )
    assert result.returncode == 0, (
        f"deploy.c failed to compile with an independent caller:\n"
        f"{result.stdout}\n{result.stderr}"
    )
    result = subprocess.run(
        [executable], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Independent behavioral tests failed:\n{result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
