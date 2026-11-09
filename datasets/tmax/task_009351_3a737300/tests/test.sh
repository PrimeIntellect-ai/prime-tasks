#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import socket
import stat
import string
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

BASE_DIR = "/home/user/mobile_pipeline"
C_SRC_DIR = os.path.join(BASE_DIR, "c_src")
CI_RUN_SH = os.path.join(BASE_DIR, "ci_run.sh")
TEST_RESULTS = os.path.join(BASE_DIR, "test_results.log")
LIB_ENCODER = os.path.join(BASE_DIR, "libencoder.so")
APP_PY = os.path.join(BASE_DIR, "app.py")
MAKEFILE = os.path.join(C_SRC_DIR, "Makefile")
CURL_TRACE = "/tmp/ci_curl_trace.log"


def request_json(payload):
    req = urllib.request.Request(
        "http://localhost:8080/encode",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            raw = response.read().decode("utf-8")
            return response.getcode(), json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            body = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            body = raw
        return exc.code, body


def start_app():
    proc = subprocess.Popen(
        ["python3", APP_PY],
        cwd=BASE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("app.py exited before the server became ready")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                time.sleep(0.15)
                if proc.poll() is not None:
                    pytest.fail("app.py could not bind to port 8080")
                return proc
        except OSError:
            time.sleep(0.1)
    proc.terminate()
    proc.wait(timeout=5)
    pytest.fail("app.py did not become ready on port 8080")


def stop_app(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


@pytest.fixture(scope="session", autouse=True)
def run_ci_script():
    """Run the CI script with an instrumented real curl before tests."""
    if os.path.exists(TEST_RESULTS):
        os.remove(TEST_RESULTS)
    if os.path.exists(CURL_TRACE):
        os.remove(CURL_TRACE)

    if os.path.isfile(CI_RUN_SH) and os.access(CI_RUN_SH, os.X_OK):
        real_curl = shutil.which("curl")
        assert real_curl, "curl is not installed"
        wrapper_dir = tempfile.mkdtemp(prefix="curl-wrapper-")
        wrapper = os.path.join(wrapper_dir, "curl")
        with open(wrapper, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf 'CALL' >> \"$CURL_TRACE\"\n")
            f.write("for arg in \"$@\"; do printf '\\t%s' \"$arg\" >> \"$CURL_TRACE\"; done\n")
            f.write("printf '\\n' >> \"$CURL_TRACE\"\n")
            f.write("exec \"$REAL_CURL\" \"$@\"\n")
        os.chmod(wrapper, 0o755)
        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        env["REAL_CURL"] = real_curl
        env["CURL_TRACE"] = CURL_TRACE
        try:
            subprocess.run([CI_RUN_SH], cwd=BASE_DIR, timeout=30, env=env)
        finally:
            shutil.rmtree(wrapper_dir, ignore_errors=True)
    yield


def test_ci_run_script_exists_and_executable():
    assert os.path.isfile(CI_RUN_SH), f"{CI_RUN_SH} does not exist."
    st = os.stat(CI_RUN_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{CI_RUN_SH} is not executable."


def test_shared_library_compiled():
    assert os.path.isfile(LIB_ENCODER), f"{LIB_ENCODER} was not found in {BASE_DIR}."
    output = subprocess.check_output(["file", LIB_ENCODER]).decode("utf-8")
    assert "shared object" in output.lower(), f"{LIB_ENCODER} is not a valid shared object."


def test_makefile_really_builds_pic_shared_library():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} does not exist."
    subprocess.run(["make", "clean"], cwd=C_SRC_DIR, check=True, timeout=10)
    dry_run = subprocess.run(
        ["make", "-B", "-n"], cwd=C_SRC_DIR, check=True, timeout=10,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    ).stdout
    assert re.search(r"(?:^|\s)-f(?:PIC|pic)(?:\s|$)", dry_run, re.MULTILINE), \
        "The actual Makefile compile command does not use -fPIC/-fpic."
    assert re.search(r"(?:^|\s)-shared(?:\s|$)", dry_run, re.MULTILINE), \
        "The actual Makefile link command does not use -shared."

    subprocess.run(["make"], cwd=C_SRC_DIR, check=True, timeout=10)
    built_library = os.path.join(C_SRC_DIR, "libencoder.so")
    assert os.path.isfile(built_library), "make did not produce c_src/libencoder.so"
    output = subprocess.check_output(["file", built_library]).decode("utf-8")
    assert "shared object" in output.lower(), "Makefile output is not a shared object"
    symbols = subprocess.check_output(["nm", "-D", built_library]).decode("utf-8")
    assert re.search(r"\bencode_data\b", symbols), "libencoder.so does not export encode_data"


def test_test_results_log():
    assert os.path.isfile(TEST_RESULTS), f"{TEST_RESULTS} was not created."
    with open(TEST_RESULTS, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert len(lines) == 6, f"Expected exactly 6 lines in {TEST_RESULTS}, found {len(lines)}."
    expected = ["200", "200", "200", "200", "200", "429"]
    assert lines == expected, f"Expected statuses {expected}, but got {lines}."


def test_ci_really_uses_curl_for_six_valid_posts():
    assert os.path.isfile(CURL_TRACE), "ci_run.sh did not invoke curl from PATH"
    with open(CURL_TRACE, "r") as f:
        calls = [line.rstrip("\n").split("\t")[1:] for line in f if line.startswith("CALL")]

    target = "http://localhost:8080/encode"
    encode_calls = []
    for args in calls:
        joined = " ".join(args)
        if target in args and "test_string" in joined:
            encode_calls.append(args)

    assert len(encode_calls) == 6, \
        f"Expected exactly 6 curl requests with the required endpoint and payload, found {len(encode_calls)}"
    for args in encode_calls:
        joined = " ".join(args)
        has_data = any(
            arg in ("-d", "--data", "--data-raw", "--data-binary")
            or arg.startswith("--data=")
            or arg.startswith("--data-raw=")
            or arg.startswith("--data-binary=")
            for arg in args
        )
        assert has_data and '"text"' in joined and "test_string" in joined, \
            "Each integration request must POST the required JSON payload using curl"

    with open(CI_RUN_SH, "r") as f:
        script = f.read()
    assert "app.py" in script, "ci_run.sh does not start app.py"


def test_app_py_validation_and_rate_limiting():
    assert os.path.isfile(APP_PY), f"{APP_PY} does not exist."
    with open(APP_PY, "r") as f:
        content = f.read()

    assert "Limiter" in content or "429" in content, "Could not find rate limiting logic in app.py."
    assert "50" in content, "Could not find length validation (< 50) in app.py."
    assert "400" in content, "Could not find 400 Bad Request logic in app.py."


def test_app_py_behavior():
    proc = start_app()
    try:
        status, data = request_json({"text": "hello"})
        assert status == 200
        assert "encoded" in data

        status, _ = request_json({"text": "a" * 55})
        assert status == 400, f"Expected 400 for long text, got {status}"

        status, _ = request_json({"text": "hello\u2022"})
        assert status == 400, f"Expected 400 for non-ASCII text, got {status}"
    finally:
        stop_app(proc)


def test_encoded_value_is_correct_for_derived_input():
    alphabet = string.ascii_lowercase[:-1]
    text = "".join(random.SystemRandom().choice(alphabet) for _ in range(23))
    expected = "".join(chr(ord(ch) + 1) for ch in reversed(text))
    proc = start_app()
    try:
        status, body = request_json({"text": text})
        assert status == 200
        assert isinstance(body, dict)
        assert isinstance(body.get("encoded"), str)
        assert body["encoded"] == expected, \
            f"Expected the C encoder result {expected!r}, got {body.get('encoded')!r}"

        valid_49 = "b" * 49
        status, body = request_json({"text": valid_49})
        assert status == 200, "A 49-character ASCII string must be accepted"
        expected_49 = "".join(chr(ord(ch) + 1) for ch in reversed(valid_49))
        assert body.get("encoded") == expected_49

        status, _ = request_json({"text": "b" * 50})
        assert status == 400, "A 50-character string must be rejected"
    finally:
        stop_app(proc)


@pytest.mark.parametrize("payload", [
    {},
    {"other": "value"},
    {"text": None},
    {"text": 123},
    {"text": ["abc"]},
])
def test_missing_and_non_string_text_are_rejected(payload):
    proc = start_app()
    try:
        status, _ = request_json(payload)
        assert status == 400, f"Expected 400 for invalid payload {payload!r}, got {status}"
    finally:
        stop_app(proc)


def test_rate_limit_is_enforced_by_running_app():
    proc = start_app()
    try:
        text = "rate_" + "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(10))
        statuses = [request_json({"text": text})[0] for _ in range(6)]
        assert statuses == [200, 200, 200, 200, 200, 429], \
            f"Running app did not enforce five requests per minute: {statuses}"
    finally:
        stop_app(proc)


def test_app_invokes_the_loaded_c_library():
    marker = "/tmp/encoder_probe_" + next(tempfile._get_candidate_names())
    sentinel = "C_PROBE"
    probe_source = marker + ".c"
    probe_library = marker + ".so"
    backup_library = marker + ".backup.so"

    with open(probe_source, "w") as f:
        f.write('#include <stdio.h>\n#include <string.h>\n')
        f.write('void encode_data(const char *input, char *output) {\n')
        f.write(f'  FILE *fp = fopen("{marker}", "w");\n')
        f.write('  if (fp) { fputs(input, fp); fclose(fp); }\n')
        f.write(f'  strcpy(output, "{sentinel}");\n')
        f.write('}\n')

    shutil.copy2(LIB_ENCODER, backup_library)
    proc = None
    try:
        subprocess.run(
            ["gcc", "-fPIC", "-shared", "-o", probe_library, probe_source],
            check=True, timeout=10,
        )
        os.replace(probe_library, LIB_ENCODER)
        probe_input = "probeinputvalue"
        proc = start_app()
        status, body = request_json({"text": probe_input})
        assert status == 200
        assert body.get("encoded") == sentinel, \
            "app.py did not return the response supplied by the loaded C library"
        assert os.path.isfile(marker), "The probe C encode_data function was not called"
        with open(marker, "r") as f:
            assert f.read() == probe_input
    finally:
        if proc is not None:
            stop_app(proc)
        shutil.copy2(backup_library, LIB_ENCODER)
        for path in (marker, probe_source, probe_library, backup_library):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
