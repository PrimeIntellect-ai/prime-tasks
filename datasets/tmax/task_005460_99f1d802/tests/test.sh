#!/bin/bash
set -e
mkdir -p /logs/verifier

script_status=0
if [ -x /home/user/fix_and_test.sh ]; then
    timeout 900 /home/user/fix_and_test.sh >/tmp/fix_and_test.out 2>/tmp/fix_and_test.err || script_status=$?
else
    script_status=127
fi
export SCRIPT_RUN_STATUS="$script_status"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import time
import urllib.error
import urllib.request


def test_fix_and_test_script_exists_and_executable():
    path = "/home/user/fix_and_test.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."


def test_fix_and_test_script_runs_successfully():
    status = int(os.environ.get("SCRIPT_RUN_STATUS", "127"))
    assert status == 0, f"fix_and_test.sh failed or timed out with status {status}"


def test_proto_file_fixed():
    path = "/home/user/api-gateway/proto/service.proto"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    assert "int32 id = 1;" in content, "Proto file was not fixed; 'int32 id = 1;' not found."
    assert "integer id = 1;" not in content, "Proto file still contains the syntax error 'integer id = 1;'."


def test_build_rs_created():
    path = "/home/user/api-gateway/build.rs"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    assert 'tonic_build::compile_protos("proto/service.proto")?' in content, "build.rs does not contain the required tonic_build command."


def test_main_rs_fixed():
    path = "/home/user/api-gateway/src/main.rs"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()
    assert "get_record(req.id);" in content, "main.rs was not fixed; 'get_record(req.id);' not found."
    assert "fetch_record(req.id);" not in content, "main.rs still contains the typo 'fetch_record(req.id);'."


def test_project_compiles_with_cargo():
    binary = "/home/user/api-gateway/target/debug/api-gateway"
    if os.path.lexists(binary):
        os.remove(binary)
    result = subprocess.run(
        ["cargo", "build", "--manifest-path", "/home/user/api-gateway/Cargo.toml"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}"


def test_project_compiled():
    path = "/home/user/api-gateway/target/debug/api-gateway"
    assert os.path.isfile(path), f"Compiled binary {path} does not exist. The project may not have compiled successfully."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled binary {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled artifact {path} is not an ELF binary."


def test_test_results_log():
    path = "/home/user/test_results.log"
    assert os.path.isfile(path), f"Log file {path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert "Successful requests: 50" in content, f"Expected 'Successful requests: 50' in {path}, but got: {content}"


def test_compiled_server_handles_50_independent_random_requests():
    binary = "/home/user/api-gateway/target/debug/api-gateway"
    proc = subprocess.Popen(
        [binary],
        cwd="/home/user/api-gateway",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    def send(record_id):
        body = json.dumps({"id": record_id}).encode("utf-8")
        request = urllib.request.Request(
            "http://127.0.0.1:8080/api/record",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            status = response.status
            payload = json.loads(response.read().decode("utf-8"))
        assert status == 200, f"Request for id {record_id} returned HTTP {status}"
        assert payload == {"data": f"Record {record_id}"}, (
            f"Unexpected response for id {record_id}: {payload}"
        )

    try:
        deadline = time.monotonic() + 12
        first_id = random.SystemRandom().randint(1, 10000)
        while True:
            assert proc.poll() is None, "Compiled server exited before accepting requests."
            try:
                send(first_id)
                break
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                if time.monotonic() >= deadline:
                    raise AssertionError("Compiled server did not start on port 8080 in time.")
                time.sleep(0.2)

        rng = random.SystemRandom()
        for _ in range(49):
            assert proc.poll() is None, "Compiled server exited while requests were being tested."
            send(rng.randint(1, 10000))
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
