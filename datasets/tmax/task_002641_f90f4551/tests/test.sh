#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

GATEWAY_DIR = "/home/user/gateway"
GATEWAY_EXEC = os.path.join(GATEWAY_DIR, "gateway")
LIBVALIDATE = os.path.join(GATEWAY_DIR, "libvalidate.so")
RESPONSE_LOG = os.path.join(GATEWAY_DIR, "response.log")

EXPECTED_SOURCES = {
    "validate.h": b'''#ifndef VALIDATE_H
#define VALIDATE_H

int validate_request(const char* endpoint);

#endif
''',
    "validate.c": b'''#include <stdio.h>
#include <string.h>
#include "validate.h"

int validate_request(const char* endpoint) {
    if (strncmp(endpoint, "/api/", 5) == 0) {
        return 1; // Valid and within rate limit
    }
    return 0; // Invalid
}
''',
    "gateway.c": b'''#include <stdio.h>
#include "validate.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("{\\"error\\": \\"Missing endpoint\\"}\\n");
        return 1;
    }

    if (validate_request(argv[1])) {
        printf("{\\"status\\": 200, \\"message\\": \\"Request forwarded successfully\\"}\\n");
    } else {
        printf("{\\"status\\": 403, \\"error\\": \\"Rate limit exceeded or invalid endpoint\\"}\\n");
    }
    return 0;
}
''',
}

def assert_sources_unchanged():
    for name, expected in EXPECTED_SOURCES.items():
        path = os.path.join(GATEWAY_DIR, name)
        assert os.path.isfile(path), f"Required source file {path} is missing."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"{name} was modified; only the Makefile may be changed."

@pytest.fixture(scope="session", autouse=True)
def clean_rebuild():
    assert_sources_unchanged()

    clean = subprocess.run(
        ["make", "clean"], cwd=GATEWAY_DIR, capture_output=True, text=True
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    for path in (GATEWAY_EXEC, LIBVALIDATE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make"], cwd=GATEWAY_DIR, capture_output=True, text=True
    )
    assert build.returncode == 0, f"Clean make failed:\n{build.stdout}\n{build.stderr}"
    assert_sources_unchanged()


def test_gateway_executable_exists():
    assert os.path.isfile(GATEWAY_EXEC), f"Executable {GATEWAY_EXEC} does not exist. Did you run make after fixing the Makefile?"
    assert os.access(GATEWAY_EXEC, os.X_OK), f"File {GATEWAY_EXEC} is not executable."


def test_gateway_rpath():
    try:
        result = subprocess.run(
            ["readelf", "-d", GATEWAY_EXEC],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run readelf on {GATEWAY_EXEC}. Error: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("The 'readelf' command is not available.")

    output = result.stdout
    has_rpath = False
    for line in output.splitlines():
        if ("(RPATH)" in line or "(RUNPATH)" in line) and "[.]" in line:
            has_rpath = True
            break

    assert has_rpath, "The gateway executable does not have an RPATH or RUNPATH pointing to '.' ([.])."


def test_gateway_links_to_validate_library():
    assert os.path.isfile(LIBVALIDATE), "Clean make did not build libvalidate.so."
    dynamic = subprocess.run(
        ["readelf", "-d", GATEWAY_EXEC], capture_output=True, text=True, check=True
    ).stdout
    assert "Shared library: [libvalidate.so]" in dynamic, "gateway is not dynamically linked against libvalidate.so."

    symbols = subprocess.run(
        ["readelf", "-Ws", GATEWAY_EXEC], capture_output=True, text=True, check=True
    ).stdout
    assert any("UND" in line and "validate_request" in line for line in symbols.splitlines()), \
        "gateway does not import validate_request from the shared library."


def test_gateway_runs_without_library_environment_and_validates_inputs():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)

    token = secrets.token_hex(12)
    cases = [
        (f"/api/{token}", '{"status": 200, "message": "Request forwarded successfully"}'),
        (f"/not-api/{token}", '{"status": 403, "error": "Rate limit exceeded or invalid endpoint"}'),
    ]
    for endpoint, expected in cases:
        result = subprocess.run(
            ["./gateway", endpoint], cwd=GATEWAY_DIR, env=env,
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"gateway failed for {endpoint}: {result.stderr}"
        assert result.stdout.strip() == expected, f"Unexpected output for {endpoint}: {result.stdout!r}"


def test_response_log_exists_and_content():
    assert os.path.isfile(RESPONSE_LOG), f"Log file {RESPONSE_LOG} does not exist. Did you redirect the output?"

    with open(RESPONSE_LOG, "r") as f:
        content = f.read().strip()

    expected_content = '{"status": 200, "message": "Request forwarded successfully"}'
    assert expected_content in content, f"The file {RESPONSE_LOG} does not contain the expected success message. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
