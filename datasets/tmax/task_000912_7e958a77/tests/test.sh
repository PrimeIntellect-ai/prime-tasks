#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

if (
    set -e

    test -f /home/user/workspace/cpp/processor.cpp
    test -f /home/user/workspace/cpp/processor.h
    test -f /home/user/workspace/cpp/CMakeLists.txt
    test -f /home/user/workspace/go/server.go

    rm -rf /home/user/workspace/cpp/build
    cmake -S /home/user/workspace/cpp -B /home/user/workspace/cpp/build
    cmake --build /home/user/workspace/cpp/build

    LIB=/home/user/workspace/cpp/build/libprocessor.so
    test -f "$LIB"
    file "$LIB" | grep -q 'shared object'
    nm -D --defined-only "$LIB" | awk '$NF == "process_array" { found=1 } END { exit !found }'

    cat > /tmp/inspect_go.go <<'GO_EOF'
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        panic(err)
    }

    hasGo := false
    hasChanType := false
    hasChanOperation := false
    hasCProcess := false
    hasSortCall := false

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChanType = true
        case *ast.SendStmt:
            hasChanOperation = true
        case *ast.UnaryExpr:
            if x.Op == token.ARROW {
                hasChanOperation = true
            }
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                if id, ok := sel.X.(*ast.Ident); ok {
                    if id.Name == "C" && sel.Sel.Name == "process_array" {
                        hasCProcess = true
                    }
                    if id.Name == "sort" {
                        hasSortCall = true
                    }
                }
            }
        }
        return true
    })

    if !(hasGo && hasChanType && hasChanOperation && hasCProcess && hasSortCall) {
        os.Exit(1)
    }
}
GO_EOF
    go run /tmp/inspect_go.go -- /home/user/workspace/go/server.go

    (cd /home/user/workspace/go && go build -o /tmp/verifier-server server.go)
    file /tmp/verifier-server | grep -q 'executable'

    cat > /tmp/processor_probe.cpp <<'CPP_EOF'
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>

static std::atomic<int> active(0);

extern "C" void process_array(int* arr, int size) {
    int concurrent = active.fetch_add(1) + 1;
    const char* path = std::getenv("PROCESSOR_PROBE_LOG");
    if (path) {
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd >= 0) {
            char line[128];
            int n = std::snprintf(line, sizeof(line), "%d %d\n", size, concurrent);
            if (n > 0) write(fd, line, static_cast<size_t>(n));
            close(fd);
        }
    }

    usleep(150000);
    for (int i = 0; i < size; ++i) arr[i] *= 2;
    active.fetch_sub(1);
}
CPP_EOF
    mkdir -p /tmp/processor-probe
    g++ -std=c++11 -shared -fPIC /tmp/processor_probe.cpp -o /tmp/processor-probe/libprocessor.so
    : > /tmp/processor-probe.log

    python3 - <<'PY_EOF'
import os
import signal

port_hex = format(8080, '04X')
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(':')[-1].upper() == port_hex and fields[3] == '0A':
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(name), signal.SIGTERM)
                break
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
PY_EOF
    sleep 1

    PROCESSOR_PROBE_LOG=/tmp/processor-probe.log \
    LD_PRELOAD=/tmp/processor-probe/libprocessor.so \
    LD_LIBRARY_PATH=/tmp/processor-probe:/home/user/workspace/cpp/build \
        /tmp/verifier-server >/tmp/verifier-server.out 2>&1 &
    SERVER_PID=$!
    trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true' EXIT

    python3 - <<'PY_EOF'
import socket
import time

for _ in range(50):
    try:
        with socket.create_connection(('127.0.0.1', 8080), timeout=.2):
            break
    except OSError:
        time.sleep(.1)
else:
    raise SystemExit('server did not start on port 8080')
PY_EOF

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import random

import pytest
import requests

URL = "http://0.0.0.0:8080/process"
AUTH_HEADERS = {
    "Content-Type": "application/json",
    "Authorization": "Bearer SecretSysAdminKey123"
}

# Generated at verifier runtime so a submission cannot pass by recognizing a
# fixed collection of request bodies.
rng = random.SystemRandom()
DYNAMIC_PAYLOADS = []
for length in (4, 5, 7, 12, 19):
    values = [rng.randint(-10000, 10000) for _ in range(length)]
    if length >= 4:
        values[-1] = values[0]
    DYNAMIC_PAYLOADS.append(values)


def test_process_endpoint_success():
    url = "http://0.0.0.0:8080/process"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer SecretSysAdminKey123"
    }
    payload = {"data": [10, 3, 7, 2, 8, 5]}

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "result" in data, f"Expected 'result' key in response JSON, got: {data}"
    assert data["result"] == [4, 6, 10, 14, 16, 20], f"Expected result [4, 6, 10, 14, 16, 20], got {data['result']}"


def test_process_endpoint_unauthorized():
    url = "http://0.0.0.0:8080/process"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer WrongKey"
    }
    payload = {"data": [1, 2, 3]}

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 401, f"Expected status 401 for invalid auth, got {response.status_code}. Response: {response.text}"


def test_process_endpoint_missing_auth():
    url = "http://0.0.0.0:8080/process"
    headers = {
        "Content-Type": "application/json"
    }
    payload = {"data": [1, 2, 3]}

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")

    assert response.status_code == 401, f"Expected status 401 for missing auth, got {response.status_code}. Response: {response.text}"


def test_runtime_generated_inputs():
    for values in DYNAMIC_PAYLOADS:
        response = requests.post(URL, json={"data": values}, headers=AUTH_HEADERS, timeout=5)
        assert response.status_code == 200, response.text
        assert response.json() == {"result": sorted(x * 2 for x in values)}


def test_cpp_function_is_used_for_concurrent_halves():
    with open('/tmp/processor-probe.log') as f:
        records = [tuple(map(int, line.split())) for line in f if line.strip()]

    all_lengths = [6] + [len(x) for x in DYNAMIC_PAYLOADS]
    expected_sizes = []
    for length in all_lengths:
        expected_sizes.extend((length // 2, length - length // 2))

    assert collections.Counter(size for size, _ in records) == collections.Counter(expected_sizes), records
    assert sum(1 for _, active in records if active >= 2) >= len(all_lengths), records
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
