#!/bin/bash
set -e
mkdir -p /logs/verifier

reward=0
server_pid=""
cleanup() {
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        kill -TERM "$server_pid" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$server_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_cmakelists_updated():
    cmake_path = "/home/user/emulator_port/CMakeLists.txt"
    assert os.path.isfile(cmake_path), f"File not found: {cmake_path}"
    content = open(cmake_path, "r", encoding="utf-8").read()

    has_cxx17 = re.search(r"cxx_std_17|CMAKE_CXX_STANDARD\s+17", content, re.IGNORECASE)
    assert has_cxx17, "CMakeLists.txt does not enforce C++17 standard."

    has_threads = re.search(r"Threads::Threads", content) or re.search(r"-pthread", content)
    assert has_threads, "CMakeLists.txt does not link the Threads package."
    assert re.search(r"find_package\s*\(\s*Threads\b", content, re.IGNORECASE), \
        "CMakeLists.txt must locate the system threading library with find_package(Threads)."


def _validate_simple_yaml(text):
    assert "\t" not in text, "Workflow YAML must not use tab indentation."
    block_indent = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if block_indent is not None:
            if indent > block_indent:
                continue
            block_indent = None
        if stripped in ("---", "..."):
            continue
        candidate = stripped[2:].lstrip() if stripped.startswith("- ") else stripped
        assert re.match(r"(?:[^:#]+|['\"][^'\"]+['\"]):(?:\s.*)?$", candidate), \
            f"Malformed YAML mapping/list entry on line {lineno}: {raw!r}"
        value = candidate.split(":", 1)[1].strip()
        if value in ("|", ">", "|-", ">-", "|+", ">+"):
            block_indent = indent
        assert value.count("[") == value.count("]"), f"Unbalanced brackets on line {lineno}"
        assert value.count("{") == value.count("}"), f"Unbalanced braces on line {lineno}"


def _run_commands(lines):
    commands = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        match = re.match(r"^(\s*)(?:-\s*)?run\s*:\s*(.*)$", raw)
        if not match:
            i += 1
            continue
        base = len(match.group(1))
        value = match.group(2).strip()
        if value not in ("|", ">", "|-", ">-", "|+", ">+"):
            commands.append(value)
            i += 1
            continue
        body = []
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if nxt.strip() and len(nxt) - len(nxt.lstrip(" ")) <= base:
                break
            body.append(nxt.strip())
            i += 1
        commands.append("\n".join(body))
    return commands


def test_ci_workflow_exists_and_is_structured():
    workflow_path = "/home/user/emulator_port/.github/workflows/ci.yml"
    assert os.path.isfile(workflow_path), f"CI workflow file not found at {workflow_path}"
    content = open(workflow_path, "r", encoding="utf-8").read()
    assert "ubuntu-latest" in content, "CI workflow does not use 'ubuntu-latest' runner."
    assert "cmake" in content.lower(), "CI workflow does not appear to configure/build CMake."
    _validate_simple_yaml(content)

    lines = content.splitlines()
    jobs_indices = [i for i, line in enumerate(lines) if re.match(r"^jobs\s*:\s*(?:#.*)?$", line)]
    assert len(jobs_indices) == 1, "Workflow must contain one top-level jobs mapping."
    start = jobs_indices[0] + 1
    job_names = []
    for line in lines[start:]:
        if line.strip() and not line.startswith(" ") and not line.lstrip().startswith("#"):
            break
        m = re.match(r"^  ([A-Za-z0-9_.-]+)\s*:\s*(?:#.*)?$", line)
        if m:
            job_names.append(m.group(1))
    assert len(job_names) == 1, f"Workflow must define a single job, found: {job_names}"
    assert re.search(r"^\s+runs-on\s*:\s*['\"]?ubuntu-latest['\"]?\s*(?:#.*)?$", content, re.MULTILINE), \
        "The CI job must run on ubuntu-latest."

    commands = "\n".join(_run_commands(lines)).lower()
    assert re.search(r"\bcmake\b[^\n]*(?:-s\b|-b\b|\s\.\s*$)", commands, re.MULTILINE), \
        "Workflow must run a CMake configure command."
    assert re.search(r"\bcmake\s+--build\b", commands), "Workflow must run cmake --build."
    assert re.search(r"(?:--target\s+bf_server\b|cmake\s+--build[^\n]*\bbf_server\b)", commands), \
        "Workflow must build the bf_server target."


def test_benchmark_log_passed():
    log_path = "/home/user/emulator_port/benchmark_metrics.log"
    assert os.path.isfile(log_path), f"Benchmark log not found: {log_path}"
    content = open(log_path, "r", encoding="utf-8").read()
    assert "BENCHMARK_COMPLETE: ALL PASS" in content, \
        "Benchmark log does not indicate all tests passed."


def test_bf_server_built():
    project_dir = "/home/user/emulator_port"
    found = False
    for root, dirs, files in os.walk(project_dir):
        if "bf_server" in files:
            filepath = os.path.join(root, "bf_server")
            if os.access(filepath, os.X_OK):
                found = True
                break
    assert found, "The 'bf_server' executable was not found. Ensure the project builds successfully."
TEST_EOF

# Preserve the original final-state assertions before creating verifier artifacts.
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

project=/home/user/emulator_port
build="$project/.verifier-build"
rm -rf "$build"
cmake -S "$project" -B "$build"
cmake --build "$build" --target bf_server --parallel 2
test -x "$build/bf_server"

# A correctly completed task should not have left its benchmark server running.
pkill -x bf_server 2>/dev/null || true
sleep 0.2

"$build/bf_server" >/tmp/bf_server.stdout 2>/tmp/bf_server.stderr &
server_pid=$!
sleep 0.4
kill -0 "$server_pid"

# Execute the supplied benchmark rather than trusting its previously reported log.
python3 "$project/benchmark.py" > "$project/benchmark_metrics.log"
grep -q '^BENCHMARK_COMPLETE: ALL PASS$' "$project/benchmark_metrics.log"
kill -0 "$server_pid"

cat << 'HTTP_TEST_EOF' > /tmp/test_live_server.py
import secrets
import socket

HOST = "127.0.0.1"
PORT = 8080


def request(path):
    data = (f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n").encode("ascii")
    with socket.create_connection((HOST, PORT), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(data)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    raw = b"".join(chunks)
    assert b"\r\n\r\n" in raw, f"Response lacks an HTTP header terminator: {raw!r}"
    header, body = raw.split(b"\r\n\r\n", 1)
    lines = header.split(b"\r\n")
    status = lines[0].decode("ascii", "replace")
    headers = {}
    for line in lines[1:]:
        assert b":" in line, f"Malformed HTTP header: {line!r}"
        key, value = line.split(b":", 1)
        headers[key.strip().lower()] = value.strip().lower()
    return status, headers, body


def make_program(values):
    current = 0
    code = []
    for value in values:
        up = (value - current) % 256
        down = (current - value) % 256
        if up <= down:
            code.append("+" * up)
        else:
            code.append("-" * down)
        code.append(".")
        current = value
    return "".join(code)


# Values are chosen only at verification time, so responses cannot be hard-coded.
values = [secrets.randbelow(80) + 1 for _ in range(7)]
code = make_program(values)
status, headers, body = request("/execute?code=" + code)
assert status == "HTTP/1.1 200 OK", status
assert headers.get(b"content-type") == b"text/plain", headers
assert body == bytes(values), (body, bytes(values))

# Exercise loops, pointer movement, and all valid punctuation including comma.
loop_code = "+++++[>+++++<-]>.,"
status, headers, body = request("/execute?code=" + loop_code)
assert status == "HTTP/1.1 200 OK", status
assert headers.get(b"content-type") == b"text/plain", headers
assert body == bytes([25]), body

# Every tested non-BF character must be rejected with the mandated response.
for bad in ("x", "7", "%", "{"):
    status, headers, body = request("/execute?code=+++" + bad + ".")
    assert status == "HTTP/1.1 400 Bad Request", (bad, status)
    assert headers.get(b"content-type") == b"text/plain", (bad, headers)
    assert body == b"Invalid characters", (bad, body)
HTTP_TEST_EOF

python3 /tmp/test_live_server.py
kill -0 "$server_pid"

# Confirm the benchmark output now on disk came from a successful real run.
python3 - <<'PY'
from pathlib import Path
p = Path('/home/user/emulator_port/benchmark_metrics.log')
text = p.read_text(encoding='utf-8')
assert text.count('PASS:') == 2
assert 'FAIL:' not in text
assert 'BENCHMARK_COMPLETE: ALL PASS' in text
PY

reward=1
