#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.server
import importlib.machinery
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid

PROJECT = "/home/user/project"
SUCCESS_LOG = "/home/user/success.log"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def stop_project_server():
    subprocess.run(
        ["pkill", "-f", "python3 server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.2)


def port_8080_is_listening():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=0.3):
            return True
    except OSError:
        return False


def test_complete_submission():
    setup_py = os.path.join(PROJECT, "setup.py")
    semver_c = os.path.join(PROJECT, "semver_ext.c")
    tester_go = os.path.join(PROJECT, "tester.go")
    ci_sh = os.path.join(PROJECT, "ci.sh")

    # Preserve the original final-state assertions.
    assert os.path.isfile(setup_py), f"File {setup_py} is missing."
    with open(setup_py, "r") as f:
        setup_content = f.read()
    assert 'print "' not in setup_content, "setup.py still contains Python 2 print statements."
    assert 'print("' in setup_content or 'print' not in setup_content, "setup.py must be Python 3 compatible."

    assert os.path.isfile(semver_c), f"File {semver_c} is missing."
    with open(semver_c, "r") as f:
        semver_content = f.read()
    assert "Py_InitModule" not in semver_content, "semver_ext.c still uses Python 2 Py_InitModule."
    assert "PyModuleDef" in semver_content, "semver_ext.c missing Python 3 PyModuleDef."
    assert "PyModule_Create" in semver_content, "semver_ext.c missing Python 3 PyModule_Create."

    assert os.path.isfile(tester_go), f"File {tester_go} is missing."
    assert os.path.isfile(ci_sh), f"File {ci_sh} is missing."

    # Remove generated artifacts so ci.sh must perform the requested build and run.
    stop_project_server()
    subprocess.run(
        ["python3", "-m", "pip", "uninstall", "-y", "semver_ext", "semver-ext"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    for path in glob.glob(os.path.join(PROJECT, "*.so")) + glob.glob(os.path.join(PROJECT, "*.pyd")):
        os.remove(path)
    for path in glob.glob(os.path.join(PROJECT, "build")) + glob.glob(os.path.join(PROJECT, "*.egg-info")):
        shutil.rmtree(path, ignore_errors=True)
    tester_binary = os.path.join(PROJECT, "tester")
    if os.path.exists(tester_binary):
        os.remove(tester_binary)
    if os.path.exists(SUCCESS_LOG):
        os.remove(SUCCESS_LOG)

    timed_out = False
    result = None
    try:
        result = run(["bash", ci_sh], cwd=PROJECT, timeout=90)
    except subprocess.TimeoutExpired:
        timed_out = True

    server_left_running = port_8080_is_listening()
    stop_project_server()

    assert not timed_out, "ci.sh did not finish within 90 seconds."
    assert result.returncode == 0, f"ci.sh failed with exit code {result.returncode}:\n{result.stdout}"
    assert not server_left_running, "ci.sh left the Python server running instead of terminating it."
    assert os.path.isfile(tester_binary), "ci.sh did not build the Go tester executable."

    # Preserve the original success.log assertions, now against a freshly executed ci.sh.
    assert os.path.isfile(SUCCESS_LOG), f"File {SUCCESS_LOG} is missing. Did ci.sh run successfully?"
    with open(SUCCESS_LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert "/api/v1/pkg/1.2.4" in lines, "Expected /api/v1/pkg/1.2.4 in success.log but it was missing."
    assert "/api/v1/pkg/2.0.0" in lines, "Expected /api/v1/pkg/2.0.0 in success.log but it was missing."
    assert "/api/v1/pkg/0.9.0" not in lines, "Found /api/v1/pkg/0.9.0 in success.log, but it should have failed the version check."
    assert "/api/v1/pkg/1.0.0-alpha" not in lines, "Found /api/v1/pkg/1.0.0-alpha in success.log, but it should have failed the version check."
    assert len(lines) == 2, f"Expected exactly 2 lines in success.log, found {len(lines)}."

    # Independently compile the submitted setup.py and C source into a clean directory.
    with tempfile.TemporaryDirectory(prefix="semver-build-") as td:
        build_lib = os.path.join(td, "lib")
        build_temp = os.path.join(td, "temp")
        build = run(
            ["python3", "setup.py", "build_ext", "--build-lib", build_lib,
             "--build-temp", build_temp, "--force"],
            cwd=PROJECT,
            timeout=60,
        )
        assert build.returncode == 0, f"The submitted C extension did not compile:\n{build.stdout}"

        extension_files = []
        for suffix in importlib.machinery.EXTENSION_SUFFIXES:
            extension_files.extend(glob.glob(os.path.join(build_lib, "semver_ext*" + suffix)))
        assert extension_files, "Building setup.py did not produce a Python extension module."

        rng = secrets.SystemRandom()
        cases = []
        for _ in range(24):
            actual = tuple(rng.randrange(0, 20) for _ in range(3))
            target = tuple(rng.randrange(0, 20) for _ in range(3))
            endpoint = "/api/v1/pkg/{}.{}.{}".format(*actual)
            target_text = "{}.{}.{}".format(*target)
            cases.append([endpoint, target_text, int(actual >= target)])

        check_code = r'''
import json
import semver_ext
cases = json.loads(input())
results = []
for endpoint, target, expected in cases:
    value = semver_ext.parse_and_compare(endpoint, target)
    results.append([value, type(value) is int])
print(json.dumps(results))
'''
        env = os.environ.copy()
        env["PYTHONPATH"] = build_lib
        behavior = subprocess.run(
            ["python3", "-c", check_code],
            cwd=td,
            env=env,
            input=json.dumps(cases) + "\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert behavior.returncode == 0, f"The built extension could not be imported or called:\n{behavior.stderr}"
        try:
            results = json.loads(behavior.stdout.strip().splitlines()[-1])
        except Exception as exc:
            raise AssertionError(f"Unexpected extension output: {behavior.stdout!r}") from exc
        assert len(results) == len(cases)
        for case, observed in zip(cases, results):
            endpoint, target, expected = case
            value, is_int = observed
            assert is_int, "parse_and_compare must return a Python integer."
            assert value == expected, (
                f"parse_and_compare({endpoint!r}, {target!r}) returned {value}, expected {expected}."
            )

    # Build tester.go from source, then exercise it against unpredictable responses.
    with tempfile.TemporaryDirectory(prefix="go-tester-") as td:
        go_binary = os.path.join(td, "tester")
        go_build = run(["go", "build", "-o", go_binary, tester_go], cwd=PROJECT, timeout=60)
        assert go_build.returncode == 0, f"tester.go did not build:\n{go_build.stdout}"

        endpoints = [
            f"/api/v1/pkg/{secrets.randbelow(30)}.{secrets.randbelow(30)}.{i}?probe={uuid.uuid4().hex}"
            for i in range(8)
        ]
        shuffled = list(endpoints)
        rng.shuffle(shuffled)
        successful = set(shuffled[:4])
        statuses = {endpoint: (200 if endpoint in successful else 418) for endpoint in endpoints}

        class ConcurrentServer(http.server.ThreadingHTTPServer):
            allow_reuse_address = True
            daemon_threads = True

        class Handler(http.server.BaseHTTPRequestHandler):
            active = 0
            maximum_active = 0
            lock = threading.Lock()

            def do_GET(self):
                with Handler.lock:
                    Handler.active += 1
                    Handler.maximum_active = max(Handler.maximum_active, Handler.active)
                try:
                    time.sleep(0.30)
                    self.send_response(statuses.get(self.path, 404))
                    self.end_headers()
                    self.wfile.write(b"probe")
                finally:
                    with Handler.lock:
                        Handler.active -= 1

            def log_message(self, fmt, *args):
                pass

        server = ConcurrentServer(("127.0.0.1", 8080), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            if os.path.exists(SUCCESS_LOG):
                os.remove(SUCCESS_LOG)
            tested = run([go_binary] + endpoints, cwd=PROJECT, timeout=20)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

        assert tested.returncode == 0, f"The Go tester failed:\n{tested.stdout}"
        assert Handler.maximum_active >= 2, "The Go tester did not make requests concurrently."
        assert os.path.isfile(SUCCESS_LOG), "The Go tester did not create /home/user/success.log."
        with open(SUCCESS_LOG, "r") as f:
            observed = [line.strip() for line in f if line.strip()]
        assert len(observed) == len(successful), (
            f"Expected {len(successful)} successful endpoints, found {len(observed)}."
        )
        assert set(observed) == successful, (
            f"The Go tester logged the wrong endpoints. Expected {sorted(successful)}, got {sorted(observed)}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
