#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import subprocess
import time
import pytest

SCRIPTS = [
    "/home/user/check_versions.sh",
    "/home/user/parse_mem.sh",
    "/home/user/api.sh",
    "/home/user/ci_pipeline.sh",
]
LIB_FILE = "/home/user/lib_versions.txt"
MEM_FILE = "/home/user/valgrind_mock.log"
RESULT_FILE = "/home/user/ci_result.json"


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/check_versions.sh",
        "/home/user/parse_mem.sh",
        "/home/user/api.sh",
        "/home/user/ci_pipeline.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_ci_result_json_content():
    result_path = "/home/user/ci_result.json"
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    # Compute expected version_status
    lib_versions_path = "/home/user/lib_versions.txt"
    version_status = "LINK_OK"
    if os.path.isfile(lib_versions_path):
        with open(lib_versions_path, "r") as f:
            for line in f:
                if line.startswith("libmath_custom.so"):
                    parts = line.strip().split(" - ")
                    if len(parts) == 2:
                        v = parts[1]
                        v_parts = [int(x) for x in v.split(".")]
                        req_parts = [2, 4, 1]
                        if v_parts < req_parts:
                            version_status = "LINK_ERROR"
                        break

    # Compute expected mem_status
    valgrind_path = "/home/user/valgrind_mock.log"
    total_leaks = 0
    if os.path.isfile(valgrind_path):
        with open(valgrind_path, "r") as f:
            for line in f:
                m = re.search(r"\[WARN\] LEAK:\s+(\d+)\s+bytes", line)
                if m:
                    total_leaks += int(m.group(1))

    mem_status = f"MEM_FAIL: {total_leaks}" if total_leaks > 4096 else f"MEM_OK: {total_leaks}"

    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_path} does not contain valid JSON.")

    assert "version_status" in data, "JSON missing 'version_status' key."
    assert data["version_status"] == version_status, f"Expected version_status '{version_status}', got '{data['version_status']}'."

    assert "mem_status" in data, "JSON missing 'mem_status' key."
    expected_mem = mem_status.replace(" ", "")
    actual_mem = str(data["mem_status"]).replace(" ", "")
    assert actual_mem == expected_mem, f"Expected mem_status '{mem_status}', got '{data['mem_status']}'."


def run_script(path, timeout=5):
    completed = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=timeout
    )
    assert completed.returncode == 0, (
        f"{path} exited with {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout.rstrip("\r\n")


def write_version_fixture(version):
    with open(LIB_FILE, "w") as f:
        f.write("libc.so - 2.31.0\n")
        f.write(f"libmath_custom.so - {version}\n")
        f.write("libcrypto.so - 1.1.1\n")


def write_memory_fixture(values):
    with open(MEM_FILE, "w") as f:
        f.write("[INFO] Starting mock execution\n")
        for i, value in enumerate(values, 1):
            f.write(f"[WARN] LEAK: {value} bytes at 0x{i:04x}\n")
        # These are not lines in the specified leak format and must be ignored.
        f.write("[INFO] LEAK: 900001 bytes at 0xaaaa\n")
        f.write("[WARN] LEAK: 900002 bytes somewhere else\n")
        f.write("LEAK: 900003 bytes at 0xbbbb\n")
        f.write("[INFO] Execution finished\n")


def receive_api_response():
    deadline = time.time() + 4
    sock = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection(("127.0.0.1", 8080), timeout=1)
            break
        except OSError:
            time.sleep(0.05)
    assert sock is not None, "api.sh did not listen on port 8080"
    with sock:
        sock.settimeout(4)
        sock.sendall(
            b"GET /status HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        )
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks)


def assert_http_response(raw, expected):
    assert b"\r\n\r\n" in raw, "HTTP response lacks the required CRLF header separator"
    header_bytes, body = raw.split(b"\r\n\r\n", 1)
    lines = header_bytes.decode("iso-8859-1").split("\r\n")
    assert lines[0] == "HTTP/1.1 200 OK", f"Bad HTTP status line: {lines[0]!r}"
    headers = {}
    for line in lines[1:]:
        assert ":" in line, f"Malformed HTTP header: {line!r}"
        name, value = line.split(":", 1)
        headers[name.strip().lower()] = value.strip()
    assert "content-length" in headers, "HTTP response has no Content-Length header"
    assert int(headers["content-length"]) == len(body), "Content-Length does not match body"
    assert json.loads(body.decode("utf-8")) == expected


def stop_process_group(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=2)


def test_components_and_pipeline_behavior():
    original_lib = open(LIB_FILE, "rb").read()
    original_mem = open(MEM_FILE, "rb").read()
    original_api = open("/home/user/api.sh", "rb").read()
    original_api_mode = os.stat("/home/user/api.sh").st_mode

    try:
        # Exercise mathematical version comparison, including a multi-digit component.
        versions = [
            (f"2.3.{random.randint(0, 99)}", "LINK_ERROR"),
            ("2.4.0", "LINK_ERROR"),
            ("2.4.1", "LINK_OK"),
            (f"2.{random.randint(10, 30)}.{random.randint(0, 99)}", "LINK_OK"),
            (f"{random.randint(3, 12)}.0.0", "LINK_OK"),
        ]
        for version, expected in versions:
            write_version_fixture(version)
            assert run_script("/home/user/check_versions.sh") == expected

        # Exercise exact leak-line extraction, summation, and the strict threshold.
        memory_cases = [
            ([4096], "MEM_OK: 4096"),
            ([4096, 1], "MEM_FAIL: 4097"),
            ([random.randint(10, 500), random.randint(5000, 9000)], None),
        ]
        for values, expected in memory_cases:
            write_memory_fixture(values)
            total = sum(values)
            derived = f"MEM_FAIL: {total}" if total > 4096 else f"MEM_OK: {total}"
            assert run_script("/home/user/parse_mem.sh") == (expected or derived)

        # Exercise api.sh itself on verifier-selected fixture values.
        version = f"2.3.{random.randint(10, 99)}"
        leaks = [random.randint(2000, 3000), random.randint(2500, 3500)]
        write_version_fixture(version)
        write_memory_fixture(leaks)
        expected_api = {
            "version_status": "LINK_ERROR",
            "mem_status": f"MEM_FAIL: {sum(leaks)}",
        }
        api_proc = subprocess.Popen(
            ["/home/user/api.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True
        )
        try:
            raw = receive_api_response()
            assert_http_response(raw, expected_api)
            api_proc.wait(timeout=4)
            assert api_proc.returncode == 0, "api.sh did not exit gracefully after one request"
        finally:
            stop_process_group(api_proc)

        # Run the real CI pipeline against fresh inputs; it must overwrite the result.
        version = f"2.{random.randint(10, 20)}.{random.randint(0, 99)}"
        leaks = [random.randint(1, 1000), random.randint(1, 1000)]
        write_version_fixture(version)
        write_memory_fixture(leaks)
        with open(RESULT_FILE, "w") as f:
            f.write("not the expected result")
        completed = subprocess.run(
            ["/home/user/ci_pipeline.sh"], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=12
        )
        assert completed.returncode == 0, completed.stderr
        with open(RESULT_FILE) as f:
            assert json.load(f) == {
                "version_status": "LINK_OK",
                "mem_status": f"MEM_OK: {sum(leaks)}",
            }
        time.sleep(0.2)

        # Substitute a one-shot API to verify that ci_pipeline starts the API and
        # saves the HTTP response rather than directly fabricating fixture answers.
        marker = "/tmp/verifier_api_started"
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
        stub_total = random.randint(7000, 9000)
        stub_data = {"version_status": "LINK_OK", "mem_status": f"MEM_FAIL: {stub_total}"}
        stub_body = json.dumps(stub_data, separators=(",", ":"))
        stub = f'''#!/bin/bash
echo started > {marker}
exec python3 -c 'import socket
body={stub_body!r}.encode()
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",8080)); s.listen(1)
c,_=s.accept()
while b"\\r\\n\\r\\n" not in c.recv(4096): pass
h=b"HTTP/1.1 200 OK\\r\\nContent-Length: "+str(len(body)).encode()+b"\\r\\nContent-Type: application/json\\r\\n\\r\\n"
c.sendall(h+body); c.close(); s.close()'
'''
        with open("/home/user/api.sh", "w") as f:
            f.write(stub)
        os.chmod("/home/user/api.sh", 0o755)
        completed = subprocess.run(
            ["/home/user/ci_pipeline.sh"], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=12
        )
        assert completed.returncode == 0, completed.stderr
        assert os.path.isfile(marker), "ci_pipeline.sh did not start /home/user/api.sh"
        with open(RESULT_FILE) as f:
            assert json.load(f) == stub_data
    finally:
        with open(LIB_FILE, "wb") as f:
            f.write(original_lib)
        with open(MEM_FILE, "wb") as f:
            f.write(original_mem)
        with open("/home/user/api.sh", "wb") as f:
            f.write(original_api)
        os.chmod("/home/user/api.sh", original_api_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
