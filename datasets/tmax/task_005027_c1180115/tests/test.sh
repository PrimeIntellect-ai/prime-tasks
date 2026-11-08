#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import difflib
import hashlib
import http.server
import json
import math
import os
import signal
import socket
import subprocess
import threading
import time
from pathlib import Path

import pytest

SCRIPT_PATH = Path('/home/user/fix_and_bench.py')
PROJECT_PATH = Path('/home/user/rust_processor')
SOURCE_PATH = PROJECT_PATH / 'src/main.rs'
TARGET_PATH = PROJECT_PATH / 'target'
REPORT_PATH = Path('/home/user/report.json')
PATCH_PATH = Path('/home/user/patches/fix_1.3.1.patch')
CHECKSUMS_PATH = Path('/home/user/patches/checksums.txt')
DUMMY_PATCH_PATH = Path('/home/user/patches/fix_1.2.4.patch')
BINARY_PATH = TARGET_PATH / 'release/rust_processor'
MARKER_PATH = Path('/tmp/rust_processor_verifier_runs')

ORIGINAL_SOURCE = '''use serde::Deserialize;

#[derive(Deserialize)]
struct Response {
    status: String,
    // BUG: Missing payload field
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resp: Response = ureq::get("http://127.0.0.1:8080/data")
        .call()?
        .into_json()?;

    // BUG: Syntax error, missing semicolon
    println!("Status: {}", resp.status)
    // println!("Payload: {}", resp.payload);

    Ok(())
}
'''

# This is the required fix plus verification-only timing instrumentation. Each
# successfully completed Rust invocation appends one measured duration.
PATCHED_SOURCE = '''use serde::Deserialize;
use std::io::Write;
use std::time::Instant;

#[derive(Deserialize)]
struct Response {
    status: String,
    payload: i32,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let verifier_started = Instant::now();
    let resp: Response = ureq::get("http://127.0.0.1:8080/data")
        .call()?
        .into_json()?;

    println!("Status: {}", resp.status);
    println!("Payload: {}", resp.payload);

    let elapsed_ns = verifier_started.elapsed().as_nanos();
    let mut marker = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/rust_processor_verifier_runs")?;
    writeln!(marker, "{}", elapsed_ns)?;

    Ok(())
}
'''

RUN = {}


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            h.update(block)
    return h.hexdigest()


def kill_port_8080_listeners():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                inodes.add(fields[9])
    if not inodes:
        return
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    try:
                        os.kill(int(proc.name), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.3)


def prepare_clean_task_state():
    assert SCRIPT_PATH.is_file(), f'Required orchestration script missing: {SCRIPT_PATH}'
    assert not SCRIPT_PATH.is_symlink(), 'fix_and_bench.py must be a real file'
    compile(SCRIPT_PATH.read_bytes(), str(SCRIPT_PATH), 'exec')

    kill_port_8080_listeners()
    subprocess.run(['rm', '-rf', str(TARGET_PATH)], check=True)
    REPORT_PATH.unlink(missing_ok=True)
    MARKER_PATH.unlink(missing_ok=True)
    SOURCE_PATH.write_text(ORIGINAL_SOURCE)

    patch = ''.join(difflib.unified_diff(
        ORIGINAL_SOURCE.splitlines(True),
        PATCHED_SOURCE.splitlines(True),
        fromfile='a/src/main.rs',
        tofile='b/src/main.rs',
    ))
    PATCH_PATH.write_text(patch)
    checksum_131 = sha256(PATCH_PATH)
    checksum_124 = sha256(DUMMY_PATCH_PATH)
    CHECKSUMS_PATH.write_text(f'1.3.1 {checksum_131}\n1.2.4 {checksum_124}\n')


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    prepare_clean_task_state()
    started = time.monotonic()
    proc = subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=600,
    )
    RUN['elapsed_ms'] = (time.monotonic() - started) * 1000.0
    RUN['stdout'] = proc.stdout
    RUN['stderr'] = proc.stderr
    assert proc.returncode == 0, (
        f'fix_and_bench.py failed with exit code {proc.returncode}\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    yield
    kill_port_8080_listeners()


def load_report():
    assert REPORT_PATH.is_file(), f'Report file not found at {REPORT_PATH}'
    try:
        return json.loads(REPORT_PATH.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {REPORT_PATH} is not valid JSON: {exc}')


def measured_runs_ms():
    assert MARKER_PATH.is_file(), 'The compiled Rust application did not complete any instrumented runs'
    lines = [line.strip() for line in MARKER_PATH.read_text().splitlines() if line.strip()]
    assert len(lines) == 5, f'Expected exactly 5 successful Rust runs, observed {len(lines)}'
    values = []
    for line in lines:
        ns = int(line)
        assert ns > 0
        values.append(ns / 1_000_000.0)
    return values


def test_report_json_exists_and_valid():
    data = load_report()
    expected_keys = {'resolved_version', 'patch_checksum', 'average_time_ms', 'mock_hit'}
    assert expected_keys.issubset(data.keys()), f'Report JSON is missing required keys. Found: {list(data.keys())}'
    assert set(data.keys()) == expected_keys, f'Report must contain the exact required keys, found: {list(data.keys())}'


def test_report_resolved_version():
    data = load_report()
    assert data['resolved_version'] == '1.3.1', f"Expected resolved_version to be '1.3.1', got '{data.get('resolved_version')}'"


def test_report_patch_checksum():
    assert PATCH_PATH.is_file(), f'Patch file missing: {PATCH_PATH}'
    expected_hash = sha256(PATCH_PATH)
    data = load_report()
    assert data['patch_checksum'] == expected_hash, f"Expected patch_checksum to be '{expected_hash}', got '{data.get('patch_checksum')}'"


def test_patch_was_applied():
    assert SOURCE_PATH.read_text() == PATCHED_SOURCE, 'The verified patch was not correctly applied to src/main.rs'


def test_report_mock_hit_and_exactly_five_runs():
    data = load_report()
    assert data['mock_hit'] is True, f"Expected mock_hit to be true, got {data.get('mock_hit')}"
    measured_runs_ms()


def test_report_average_time_ms():
    data = load_report()
    avg_time = data.get('average_time_ms')
    assert isinstance(avg_time, (int, float)) and not isinstance(avg_time, bool), 'average_time_ms must be a number'
    assert math.isfinite(avg_time) and avg_time > 0.0, f'Expected finite average_time_ms > 0.0, got {avg_time}'
    internal_avg = sum(measured_runs_ms()) / 5.0
    # subprocess timing includes process startup, so it should be near and not
    # materially below the application's own measured request/runtime interval.
    assert avg_time >= internal_avg * 0.5, f'Reported average {avg_time} ms is inconsistent with measured runs ({internal_avg} ms)'
    assert avg_time <= internal_avg * 5.0 + 100.0, f'Reported average {avg_time} ms is inconsistent with measured runs ({internal_avg} ms)'
    assert avg_time <= RUN['elapsed_ms'], 'Reported benchmark average exceeds the entire orchestration runtime'


def test_rust_binary_compiled():
    assert BINARY_PATH.is_file(), f'Compiled binary not found at {BINARY_PATH}'
    assert not BINARY_PATH.is_symlink(), 'Compiled binary must not be a symlink'
    assert os.access(BINARY_PATH, os.X_OK), f'Binary at {BINARY_PATH} is not executable'
    raw = BINARY_PATH.read_bytes()
    assert raw.startswith(b'\x7fELF'), 'The release artifact is not a native ELF executable'
    assert b'rust_eh_personality' in raw or b'library/std/src' in raw or b'panicked at' in raw, 'Release artifact does not contain expected Rust runtime material'
    fingerprint = TARGET_PATH / 'release/.fingerprint'
    assert fingerprint.is_dir() and any(fingerprint.iterdir()), 'Cargo release build metadata is missing'


def test_compiled_binary_fetches_exact_mock_response():
    kill_port_8080_listeners()
    hits = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            hits.append(self.path)
            if self.path != '/data':
                self.send_response(404)
                self.end_headers()
                return
            body = b'{"status": "success", "payload": 42}'
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    server = http.server.HTTPServer(('127.0.0.1', 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        proc = subprocess.run([str(BINARY_PATH)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    assert proc.returncode == 0, f'Compiled Rust binary failed: {proc.stderr}'
    assert hits == ['/data'], f'Expected one GET /data request, observed {hits}'
    assert 'Status: success' in proc.stdout
    assert 'Payload: 42' in proc.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
