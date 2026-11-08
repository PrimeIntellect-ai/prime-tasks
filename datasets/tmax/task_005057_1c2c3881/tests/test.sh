#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request


def test_validator_rs_fixed():
    file_path = "/home/user/polyglot/validator.rs"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()

    assert "fn get_token<'a>() -> &'a str" not in content or "String::from" not in content, \
        "validator.rs still appears to return a borrowed reference to a local variable."


def test_parser_c_fixed():
    file_path = "/home/user/polyglot/parser.c"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()

    assert "strcpy(" not in content, "parser.c still contains the vulnerable strcpy function."
    assert "strncpy(" in content, "parser.c does not use the secure strncpy function."


def test_logger_go_fixed():
    file_path = "/home/user/polyglot/logger.go"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()

    assert "Mutex" in content, "logger.go does not use a Mutex to prevent race conditions."


def test_gateway_builds_and_serves():
    gateway = "/home/user/gateway.py"
    workdir = "/home/user/polyglot"
    log_path = "/home/user/build_output.log"
    validator = os.path.join(workdir, "validator")
    parser = os.path.join(workdir, "libparser.so")
    logger = os.path.join(workdir, "logger")

    assert os.path.isfile(gateway), f"The file {gateway} is missing."
    assert os.access(gateway, os.X_OK), f"The file {gateway} is not executable."

    for path in (validator, parser, logger, log_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        [gateway], cwd=workdir, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    backup = None
    try:
        deadline = time.time() + 90
        while time.time() < deadline:
            assert proc.poll() is None, "gateway.py exited before serving on port 8080"
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                    break
            except OSError:
                time.sleep(0.25)
        else:
            raise AssertionError("gateway.py did not start an HTTP server on port 8080")

        for path in (validator, parser, logger):
            assert os.path.isfile(path), f"gateway.py did not build {path}"
            with open(path, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF artifact"
        assert os.access(validator, os.X_OK), "Rust validator is not executable"
        assert os.access(logger, os.X_OK), "Go logger is not executable"

        rust_run = subprocess.run(
            [validator], input=b"probe-token\n", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert rust_run.returncode == 0, rust_run.stderr.decode(errors="replace")
        assert rust_run.stdout.decode(errors="replace").strip() == "VALID"

        go_run = subprocess.run(
            [logger], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert go_run.returncode == 0, go_run.stderr.decode(errors="replace")
        assert "Done" in go_run.stdout.decode(errors="replace")

        race_binary = "/tmp/logger-race"
        race_build = subprocess.run(
            ["go", "build", "-race", "-o", race_binary, "logger.go"],
            cwd=workdir, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90
        )
        assert race_build.returncode == 0, race_build.stderr.decode(errors="replace")
        race_run = subprocess.run(
            [race_binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        race_text = (race_run.stdout + race_run.stderr).decode(errors="replace")
        assert race_run.returncode == 0, race_text
        assert "DATA RACE" not in race_text, race_text

        lib = ctypes.CDLL(parser)
        assert hasattr(lib, "parse"), "libparser.so does not export parse"
        lib.parse.argtypes = [ctypes.c_char_p]
        lib.parse.restype = None
        lib.parse(b"test payload")

        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass

        bad_req = urllib.request.Request(
            "http://127.0.0.1:8080/process", data=b'{"token":',
            headers={"Content-Type": "application/json"}, method="POST"
        )
        try:
            urllib.request.urlopen(bad_req, timeout=5)
            raise AssertionError("Malformed JSON was accepted by /process")
        except urllib.error.HTTPError as exc:
            assert 400 <= exc.code < 500, f"Malformed JSON returned HTTP {exc.code}"
        assert proc.poll() is None, "Malformed JSON crashed the gateway"
        assert not os.path.exists(log_path), "Malformed JSON created the success log"

        token = "verify-" + secrets.token_hex(16)
        trace = "/tmp/gateway_validator_stdin"
        try:
            os.unlink(trace)
        except FileNotFoundError:
            pass

        backup = validator + ".verified-build"
        os.replace(validator, backup)
        with open(validator, "w") as f:
            f.write("#!/bin/sh\ncat > /tmp/gateway_validator_stdin\nprintf 'VALID\\n'\n")
        os.chmod(validator, 0o755)

        body = json.dumps({"token": token, "data": "payload"}).encode()
        req = urllib.request.Request(
            "http://127.0.0.1:8080/process", data=body,
            headers={"Content-Type": "application/json"}, method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            assert 200 <= response.status < 300, f"Valid request returned HTTP {response.status}"
            response.read()

        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(log_path):
            time.sleep(0.1)
        assert os.path.isfile(trace), "The gateway did not invoke the validator via standard input"
        with open(trace, "rb") as f:
            assert f.read().decode(errors="replace").strip() == token, \
                "The gateway did not pass the request token to the validator"
        assert os.path.isfile(log_path), "A valid token did not create build_output.log"
        with open(log_path, "r") as f:
            assert f.read().strip() == "BUILD_AND_SECURE_COMPLETE"
    finally:
        if backup and os.path.exists(backup):
            try:
                os.unlink(validator)
            except FileNotFoundError:
                pass
            os.replace(backup, validator)
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_build_output_log_exists_and_correct():
    file_path = "/home/user/build_output.log"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. The gateway script may not have been run or failed to verify the token."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert "BUILD_AND_SECURE_COMPLETE" in content, \
        f"The build_output.log does not contain the expected success message. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
