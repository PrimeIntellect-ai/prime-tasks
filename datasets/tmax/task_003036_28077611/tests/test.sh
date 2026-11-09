#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import stat
import subprocess
import tempfile

APP_DIR = "/home/user/app"
MOCK_C = os.path.join(APP_DIR, "mock_crypto.c")
MOCK_SO = os.path.join(APP_DIR, "libmock_crypto.so")
TEST_SH = os.path.join(APP_DIR, "test_fixture.sh")
TEST_LOG = os.path.join(APP_DIR, "test_result.log")
SERVER = os.path.join(APP_DIR, "server_bin")
AUTH_SO = os.path.join(APP_DIR, "libauth.so")


def clean_env():
    env = os.environ.copy()
    env.pop("LD_PRELOAD", None)
    env.pop("LD_LIBRARY_PATH", None)
    return env


def check_library_behavior(path):
    code = r'''
import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.verify_signature
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_int
values = [fn(b"user_payload"), fn(b""), fn(b"arbitrary input")]
print(" ".join(map(str, values)))
'''
    result = subprocess.run(
        ["python3", "-c", code, path], capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"Calling verify_signature(const char *) in {path} failed: {result.stderr}"
    )
    assert result.stdout.strip() == "1 1 1", (
        f"verify_signature must return 1 for every supplied const char * argument; "
        f"got {result.stdout!r}"
    )


def test_mock_c_exists():
    assert os.path.isfile(MOCK_C), f"Expected {MOCK_C} to exist."


def test_mock_so_exists():
    assert os.path.isfile(MOCK_SO), f"Expected {MOCK_SO} to exist."
    elf = subprocess.run(["readelf", "-h", MOCK_SO], capture_output=True, text=True)
    assert elf.returncode == 0, f"Expected {MOCK_SO} to be an ELF shared library."
    assert "DYN (Shared object file)" in elf.stdout, f"Expected {MOCK_SO} to be a shared object."


def test_test_fixture_exists_and_executable():
    assert os.path.isfile(TEST_SH), f"Expected {TEST_SH} to exist."
    assert os.access(TEST_SH, os.X_OK), f"Expected {TEST_SH} to be executable."


def test_mock_so_exports_verify_signature():
    # Retain the original export assertion and additionally require a defined function.
    result = subprocess.run(["nm", "-D", MOCK_SO], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run nm on {MOCK_SO}"
    assert "verify_signature" in result.stdout, f"verify_signature symbol not found in {MOCK_SO}"
    assert re.search(r"^[0-9a-fA-F]+\s+[TW]\s+verify_signature(?:@@?\S+)?$", result.stdout, re.M), (
        "libmock_crypto.so must define and export verify_signature"
    )
    check_library_behavior(MOCK_SO)


def test_mock_source_builds_and_implements_required_function():
    # Build the submitted source independently so an unrelated prebuilt library cannot pass.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "rebuilt_mock.so")
        result = subprocess.run(
            ["gcc", "-fPIC", "-shared", "-Wall", "-Wextra",
             "-Werror=strict-prototypes", "-o", rebuilt, MOCK_C],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"mock_crypto.c did not build as a shared library: {result.stderr}"
        check_library_behavior(rebuilt)


def test_server_runs_with_submitted_library():
    env = clean_env()
    env["LD_PRELOAD"] = MOCK_SO
    result = subprocess.run([SERVER], cwd=APP_DIR, env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"server_bin failed with libmock_crypto.so: {result.stderr}"
    assert result.stdout == "Starting authentication...\nAuthentication Success\n", (
        f"Unexpected server_bin stdout: {result.stdout!r}"
    )


def test_test_result_log_contents():
    # First retain the original behavior check against the real server.
    if os.path.exists(TEST_LOG):
        os.remove(TEST_LOG)

    result = subprocess.run([TEST_SH], cwd=APP_DIR, env=clean_env(), capture_output=True, text=True)
    assert result.returncode == 0, f"{TEST_SH} failed to execute properly. Stderr: {result.stderr}"
    assert os.path.isfile(TEST_LOG), f"{TEST_LOG} was not created by {TEST_SH}."

    with open(TEST_LOG, "r") as f:
        content = f.read()
    assert "Authentication Success" in content, f"Expected 'Authentication Success' in {TEST_LOG}, but got: {content}"
    assert content == "Starting authentication...\nAuthentication Success\n", (
        "test_result.log must contain exactly server_bin's standard output"
    )

    # Replace server_bin temporarily with a fresh probe whose output and marker cannot have
    # been hard-coded in the submitted fixture. The probe still depends on libauth.so and its
    # unresolved verify_signature symbol, so successful execution requires injection.
    nonce = secrets.token_hex(24)
    marker = os.path.join("/tmp", "server_probe_" + secrets.token_hex(24))
    source = f'''
#include <stdio.h>
extern int authenticate_user(void);
int main(void) {{
    FILE *f = fopen({json.dumps(marker)}, "w");
    if (f) {{ fputs("executed", f); fclose(f); }}
    int rc = authenticate_user();
    printf("Probe nonce: %s\\n", {json.dumps(nonce)});
    return rc;
}}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        probe = os.path.join(td, "server_probe")
        with open(src, "w") as f:
            f.write(source)
        built = subprocess.run(
            ["gcc", "-o", probe, src, "-L" + APP_DIR, "-lauth",
             "-Wl,-rpath=.", "-Wl,--allow-shlib-undefined"],
            capture_output=True, text=True,
        )
        assert built.returncode == 0, f"Verifier could not build execution probe: {built.stderr}"

        with open(SERVER, "rb") as f:
            original_server = f.read()
        original_mode = stat.S_IMODE(os.stat(SERVER).st_mode)

        try:
            with open(probe, "rb") as f:
                probe_bytes = f.read()
            with open(SERVER, "wb") as f:
                f.write(probe_bytes)
            os.chmod(SERVER, 0o755)

            if os.path.exists(marker):
                os.remove(marker)
            if os.path.exists(TEST_LOG):
                os.remove(TEST_LOG)

            run = subprocess.run([TEST_SH], cwd=APP_DIR, env=clean_env(), capture_output=True, text=True)
            assert run.returncode == 0, f"Fixture failed to run the server probe: {run.stderr}"
            assert os.path.exists(marker), "test_fixture.sh did not actually execute ./server_bin"
            assert os.path.isfile(TEST_LOG), "Fixture did not create test_result.log for the server probe"
            with open(TEST_LOG, "r") as f:
                probe_log = f.read()
            expected = (
                "Starting authentication...\n"
                "Authentication Success\n"
                f"Probe nonce: {nonce}\n"
            )
            assert probe_log == expected, (
                "test_fixture.sh must inject libmock_crypto.so and capture exactly the executed "
                f"server_bin stdout; expected {expected!r}, got {probe_log!r}"
            )
        finally:
            with open(SERVER, "wb") as f:
                f.write(original_server)
            os.chmod(SERVER, original_mode)
            if os.path.exists(marker):
                os.remove(marker)

    # Ensure the fixture did not replace or break the submitted library while running.
    check_library_behavior(MOCK_SO)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
