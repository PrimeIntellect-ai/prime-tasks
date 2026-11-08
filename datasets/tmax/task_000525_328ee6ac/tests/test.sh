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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import requests

WORKSPACE = Path('/home/user/workspace')
BUILD_SCRIPT = Path('/home/user/build.sh')


def decode_expected_versions():
    cmd = [
        'ffmpeg', '-v', 'error', '-i', '/app/telemetry.mp4',
        '-vf', 'fps=1,scale=1:1', '-pix_fmt', 'gray',
        '-f', 'rawvideo', 'pipe:1'
    ]
    pixels = subprocess.check_output(cmd, timeout=30)
    assert len(pixels) >= 36, f'Telemetry contained only {len(pixels)} decoded frames'
    bits = ''.join('1' if value >= 128 else '0' for value in pixels[:36])
    a = int(bits[0:12], 2)
    b = int(bits[12:24], 2)
    c = int(bits[24:36], 2)
    solutions = [
        (x, y, z)
        for x in range(1, 31)
        for y in range(1, 31)
        for z in range(1, 31)
        if x + y + z == a
        and x * y + z == b
        and x * x + y * y - z == c
    ]
    assert len(solutions) == 1, f'Expected a unique telemetry solution, got {solutions}'
    x, y, z = solutions[0]
    return {'python': f'3.{x}', 'node': str(y), 'go': f'1.{z}'}


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A':
                continue
            local_port = int(fields[1].rsplit(':', 1)[1], 16)
            if local_port == port:
                inodes.add(fields[9])

    owners = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    owners.add(int(proc.name))
        except (OSError, PermissionError):
            continue
    return owners


def assert_go_listener(port):
    pids = listener_pids(port)
    assert pids, f'No listening process found for port {port}'
    diagnostics = []
    for pid in pids:
        exe = f'/proc/{pid}/exe'
        result = subprocess.run(
            ['go', 'version', '-m', exe], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        diagnostics.append(f'pid={pid}: {result.stdout.strip()}')
        if result.returncode == 0 and re.search(r'\bgo1\.\d+', result.stdout):
            return
    raise AssertionError(
        f'Listener on port {port} is not a Go executable: ' + '; '.join(diagnostics)
    )


def test_go_implementation_solver_and_fixture():
    assert WORKSPACE.is_dir(), f'Missing workspace {WORKSPACE}'
    go_files = sorted(WORKSPACE.rglob('*.go'))
    production_files = [p for p in go_files if not p.name.endswith('_test.go')]
    test_files = [p for p in go_files if p.name.endswith('_test.go')]
    assert production_files, 'No Go implementation exists in /home/user/workspace'
    assert test_files, 'No Go constraint-solver test fixture (*_test.go) exists'

    source = '\n'.join(p.read_text(errors='replace') for p in production_files).lower()
    compact = re.sub(r'[\s()]', '', source)
    assert 'x+y+z' in compact, 'Go source does not implement the X + Y + Z constraint'
    assert 'x*y+z' in compact, 'Go source does not implement the X * Y + Z constraint'
    assert 'x*x+y*y-z' in compact, 'Go source does not implement the X^2 + Y^2 - Z constraint'

    inspector = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strings"
)
func main() {
    root := os.Args[1]
    hasGo, hasChan, hasTest := false, false, false
    filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
        if err != nil || info.IsDir() || !strings.HasSuffix(path, ".go") { return nil }
        f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
        if err != nil { panic(err) }
        ast.Inspect(f, func(n ast.Node) bool {
            switch v := n.(type) {
            case *ast.GoStmt:
                hasGo = true
            case *ast.ChanType:
                hasChan = true
            case *ast.FuncDecl:
                if strings.HasSuffix(path, "_test.go") && strings.HasPrefix(v.Name.Name, "Test") {
                    hasTest = true
                }
            }
            return true
        })
        return nil
    })
    if !hasGo || !hasChan || !hasTest {
        fmt.Printf("goroutine=%v channel=%v test=%v\n", hasGo, hasChan, hasTest)
        os.Exit(1)
    }
}
'''
    Path('/tmp/inspect_go.go').write_text(inspector)
    checked = subprocess.run(
        ['go', 'run', '/tmp/inspect_go.go', str(WORKSPACE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert checked.returncode == 0, (
        'Go source must contain a goroutine, a channel, and a Go test fixture: '
        + checked.stdout
    )

    env = os.environ.copy()
    if not (WORKSPACE / 'go.mod').exists():
        env['GO111MODULE'] = 'off'
    tested = subprocess.run(
        ['go', 'test', './...'], cwd=WORKSPACE, env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
    )
    assert tested.returncode == 0, 'Go test fixture failed:\n' + tested.stdout

    assert_go_listener(8080)
    assert_go_listener(9000)


def test_http_versions_endpoint():
    try:
        response = requests.get('http://127.0.0.1:8080/versions', timeout=5)
        response.raise_for_status()
        data = response.json()
    except Exception as e:
        raise AssertionError(f'Failed to connect to HTTP server on port 8080 or invalid response: {e}')

    expected = {'python': '3.8', 'node': '14', 'go': '1.18'}
    assert data == expected, f'Expected {expected}, got {data}'
    derived = decode_expected_versions()
    assert data == derived, f'Expected telemetry-derived versions {derived}, got {data}'


def send_build():
    try:
        with socket.create_connection(('127.0.0.1', 9000), timeout=5) as sock:
            sock.sendall(b'BUILD\n')
            return sock.recv(1024).decode('utf-8')
    except Exception as e:
        raise AssertionError(f'Failed to connect to TCP server on port 9000 or communicate: {e}')


def test_tcp_build_endpoint():
    response = send_build()
    assert response == 'SUCCESS\n', f"Expected 'SUCCESS\\n' from TCP server, got {response!r}"


def test_build_script_exists_and_executable():
    assert BUILD_SCRIPT.is_file(), f'Build script missing at {BUILD_SCRIPT}'
    assert os.access(BUILD_SCRIPT, os.X_OK), f'Build script at {BUILD_SCRIPT} is not executable'
    try:
        output = subprocess.check_output([str(BUILD_SCRIPT)], text=True).strip()
    except subprocess.CalledProcessError as e:
        raise AssertionError(f'Build script failed with exit code {e.returncode}')
    expected_output = 'Building with Python 3.8, Node 14, Go 1.18'
    assert output == expected_output, f'Expected output {expected_output!r}, got {output!r}'


def test_tcp_handler_really_executes_build_script():
    original = BUILD_SCRIPT.read_bytes()
    original_mode = BUILD_SCRIPT.stat().st_mode
    marker = Path(f'/tmp/build-executed-{os.getpid()}')
    replacement = BUILD_SCRIPT.with_name('build.sh.verifier-new')
    replacement.write_text(
        '#!/bin/bash\n'
        f"printf executed > {str(marker)!r}\n"
        "echo 'Building with Python 3.8, Node 14, Go 1.18'\n"
        'exit 0\n'
    )
    replacement.chmod(0o755)
    try:
        os.replace(replacement, BUILD_SCRIPT)
        response = send_build()
        assert response == 'SUCCESS\n', f"Expected 'SUCCESS\\n', got {response!r}"
        deadline = time.time() + 5
        while time.time() < deadline and not marker.exists():
            time.sleep(0.05)
        assert marker.exists(), 'TCP BUILD handler returned success without executing /home/user/build.sh'
    finally:
        restore = BUILD_SCRIPT.with_name('build.sh.verifier-restore')
        restore.write_bytes(original)
        restore.chmod(original_mode)
        os.replace(restore, BUILD_SCRIPT)
        marker.unlink(missing_ok=True)
        replacement.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
