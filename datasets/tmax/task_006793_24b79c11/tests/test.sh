#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import urllib.error
import urllib.request


def post(port, program):
    url = f"http://127.0.0.1:{port}/execute"
    payload = json.dumps({"program": program}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read()
            assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}"
    except urllib.error.URLError as exc:
        raise AssertionError(f"Failed to connect to {url}: {exc}") from exc

    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError(f"Response from {url} is not valid JSON: {body!r}") from exc
    return body, data


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def named_block(text, kind, name):
    match = re.search(rf"\b{kind}\s+{name}\s*\{{", text)
    assert match, f"Missing {kind} {name} block"
    start = match.end() - 1
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    raise AssertionError(f"Unclosed {kind} {name} block")


def listening_processes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                rows = handle.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            columns = row.split()
            if len(columns) < 10 or columns[3] != "0A":
                continue
            if int(columns[1].rsplit(":", 1)[1], 16) == port:
                inodes.add(columns[9])

    processes = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except OSError:
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            continue
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
            status = open(f"/proc/{pid}/status", "r").read()
            uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
        except (OSError, AttributeError):
            continue
        processes.append((exe, cmdline, uid))
    return processes


def test_required_files_and_python3_server():
    for path in ("/home/user/server.py", "/home/user/nginx.conf"):
        assert os.path.isfile(path), f"File not found: {path}"
    result = subprocess.run(
        ["python3", "-m", "py_compile", "/home/user/server.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"server.py is not valid Python 3: {result.stderr}"


def test_nginx_configuration_and_running_processes():
    with open("/home/user/nginx.conf", "r") as handle:
        config = strip_comments(handle.read())

    pid_match = re.search(r"\bpid\s+([^;]+);", config)
    assert pid_match and pid_match.group(1).strip().startswith("/tmp/"), "Nginx pid must be under /tmp/"
    for match in re.finditer(r"\b\w+_temp_path\s+([^;\s]+)", config):
        assert match.group(1).startswith("/tmp/"), f"Nginx temp path is not under /tmp/: {match.group(1)}"
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", config), "Missing listen 127.0.0.1:8080"
    assert re.search(r"\blocation\s+(?:=\s*)?/execute\s*\{[^{}]*\bproxy_pass\s+http://127\.0\.0\.1:9090/?\s*;", config, re.S), "Missing /execute proxy to 127.0.0.1:9090"

    checked = subprocess.run(
        ["nginx", "-t", "-c", "/home/user/nginx.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert checked.returncode == 0, f"nginx.conf fails nginx -t: {checked.stdout}{checked.stderr}"

    backend = listening_processes(9090)
    assert any(exe.startswith("python3") and "/home/user/server.py" in cmd for exe, cmd, _ in backend), \
        f"Port 9090 is not served by Python 3 running server.py: {backend}"

    proxy = listening_processes(8080)
    assert any(exe == "nginx" for exe, _, _ in proxy), f"Port 8080 is not owned by Nginx: {proxy}"
    assert any(exe == "nginx" and "/home/user/nginx.conf" in cmd for exe, cmd, _ in proxy), \
        f"Running Nginx was not started with /home/user/nginx.conf: {proxy}"
    assert any(exe == "nginx" and uid != 0 for exe, _, uid in proxy), "Nginx has no non-root process serving port 8080"


def test_live_service():
    """Exercise both the Python API and Nginx proxy on unpredictable inputs."""
    rng = random.SystemRandom()
    a, b, c, d = [rng.randrange(11, 1000) for _ in range(4)]
    cases = [
        (f"{a} {b} ADD", a + b),
        (f"{a} {b} MUL", a * b),
        (f"{a} {b} ADD {c} MUL", (a + b) * c),
        (f"{a} {b} MUL {c} {d} MUL ADD", a * b + c * d),
    ]
    for program, expected in cases:
        backend_body, backend_data = post(9090, program)
        proxy_body, proxy_data = post(8080, program)
        assert backend_data == {"result": expected}, f"Backend gave {backend_data} for {program!r}, expected {expected}"
        assert proxy_data == {"result": expected}, f"Proxy gave {proxy_data} for {program!r}, expected {expected}"
        assert proxy_body == backend_body, "Nginx response body differs from the backend response body"

    # Keep the original live-service assertion as well.
    _, data = post(8080, "2 3 ADD")
    assert data.get("result") == 5, f"Expected result 5 for '2 3 ADD', got {data.get('result')}"


def test_migration_result_log_and_test_script():
    script_path = "/home/user/test_system.sh"
    log_path = "/home/user/migration_result.log"
    assert os.path.exists(script_path), f"File not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    with open(script_path, "r") as handle:
        script = re.sub(r"(?m)^\s*#.*$", "", handle.read())
    assert re.search(r"(^|[;&|\s])curl([\s;]|$)", script), "test_system.sh does not use curl"
    assert "http://127.0.0.1:8080/execute" in script, "test_system.sh does not call the Nginx /execute endpoint"
    assert "5 10 MUL 2 ADD" in script, "test_system.sh does not submit the required program"

    expected_body, expected_data = post(8080, "5 10 MUL 2 ADD")
    assert expected_data == {"result": 52}
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass
    run = subprocess.run(
        [script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert run.returncode == 0, f"test_system.sh failed: {run.stderr.decode('utf-8', 'replace')}"
    assert os.path.exists(log_path), f"File not found after running test_system.sh: {log_path}"
    with open(log_path, "rb") as handle:
        content_bytes = handle.read()
    assert content_bytes == expected_body, "migration_result.log is not the exact HTTP response body"

    # Keep the original JSON and result assertions.
    try:
        data = json.loads(content_bytes.decode("utf-8").strip())
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise AssertionError(f"Content of {log_path} is not valid JSON: {content_bytes!r}")
    assert "result" in data, f"Key 'result' missing in {log_path}"
    assert data["result"] == 52, f"Expected result 52, got {data['result']}"


def test_protobuf_schema():
    proto_path = "/home/user/emulator.proto"
    assert os.path.exists(proto_path), f"File not found: {proto_path}"
    with open(proto_path, "r") as handle:
        content = handle.read()

    # Preserve the original assertions.
    assert re.search(r'syntax\s*=\s*"proto3"\s*;', content), "Missing or incorrect syntax = 'proto3';"
    assert re.search(r'package\s+emulator\s*;', content), "Missing package emulator;"
    assert re.search(r'service\s+EmulatorService', content), "Missing service EmulatorService"
    assert re.search(r'rpc\s+ExecuteProgram', content), "Missing rpc ExecuteProgram"
    assert re.search(r'string\s+program\s*=\s*1\s*;', content), "Missing string program = 1;"
    assert re.search(r'int32\s+result\s*=\s*1\s*;', content), "Missing int32 result = 1;"

    # Validate that those declarations occur in the correct blocks, not comments.
    clean = strip_comments(content)
    assert re.search(r'^\s*syntax\s*=\s*"proto3"\s*;', clean), "Proto syntax declaration must be active"
    assert re.search(r'\bpackage\s+emulator\s*;', clean), "Proto package declaration must be active"
    request = named_block(clean, "message", "ProgramRequest")
    response = named_block(clean, "message", "ProgramResponse")
    service = named_block(clean, "service", "EmulatorService")
    request_fields = re.findall(r'\b(?:string|int32|int64|bool|bytes|double|float)\s+\w+\s*=\s*\d+\s*;', request)
    response_fields = re.findall(r'\b(?:string|int32|int64|bool|bytes|double|float)\s+\w+\s*=\s*\d+\s*;', response)
    assert request_fields == ["string program = 1;"] or (len(request_fields) == 1 and re.fullmatch(r'string\s+program\s*=\s*1\s*;', request_fields[0])), \
        f"ProgramRequest must contain only string program = 1; got {request_fields}"
    assert response_fields == ["int32 result = 1;"] or (len(response_fields) == 1 and re.fullmatch(r'int32\s+result\s*=\s*1\s*;', response_fields[0])), \
        f"ProgramResponse must contain only int32 result = 1; got {response_fields}"
    assert re.search(r'\brpc\s+ExecuteProgram\s*\(\s*ProgramRequest\s*\)\s+returns\s*\(\s*ProgramResponse\s*\)\s*;', service), \
        "ExecuteProgram must accept ProgramRequest and return ProgramResponse"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
