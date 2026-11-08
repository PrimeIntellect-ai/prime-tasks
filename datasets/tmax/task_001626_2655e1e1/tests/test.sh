#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import struct
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

import pytest
import yaml

BINARY = "/home/user/log_sanitizer"
TIMESTAMP = re.compile(br'(?m)^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]')


def parse_records(data):
    starts = [m.start() for m in TIMESTAMP.finditer(data)]
    return [data[starts[i]:(starts[i + 1] if i + 1 < len(starts) else len(data))]
            for i in range(len(starts))]


def expected_output(data):
    return b"".join(record for record in parse_records(data)
                    if b"[SPAM-MODULE]" not in record)


def run_binary(input_dir, output_dir, timeout=15):
    return subprocess.run([BINARY, str(input_dir), str(output_dir)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout)


def test_binary_is_compiled_executable_and_validates_arguments():
    source = Path("/home/user/log_sanitizer.c")
    binary = Path(BINARY)
    assert source.is_file(), "C source /home/user/log_sanitizer.c is missing."
    assert binary.is_file(), f"Binary {BINARY} not found."
    assert os.access(binary, os.X_OK), f"Binary {BINARY} is not executable."
    assert binary.read_bytes()[:4] == b"\x7fELF", "log_sanitizer must be a compiled executable."

    with tempfile.TemporaryDirectory() as td:
        inp = Path(td) / "in"
        out = Path(td) / "out"
        inp.mkdir()
        for argv in ([], [str(inp)], [str(inp), str(out), "extra"]):
            result = subprocess.run([BINARY, *argv], stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=5)
            assert result.returncode != 0, f"Binary accepted invalid arguments: {argv}"


def test_webapp_config():
    path = "/home/user/app/webapp/config.yaml"
    assert os.path.exists(path), f"Config file {path} missing."
    with open(path, "r") as f:
        config = yaml.safe_load(f)
    assert isinstance(config, dict), "config.yaml must contain a YAML mapping."
    assert config.get("log_dir") == "/home/user/logs/raw/", \
        "log_dir in config.yaml must be /home/user/logs/raw/"


def test_nginx_config_has_active_header_directive():
    path = "/home/user/app/nginx.conf"
    assert os.path.exists(path), f"Nginx config {path} missing."
    content = Path(path).read_text()
    assert re.search(r'(?i)X-Sanitizer-Enabled[\s:]+true', content) or \
           "X-Sanitizer-Enabled" in content, \
           "Nginx config is missing the X-Sanitizer-Enabled header injection."

    active = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r'(?im)^\s*proxy_set_header\s+X-Sanitizer-Enabled\s+(?:"true"|true)\s*;', active), \
        "The header must be set on proxied backend requests, not merely mentioned in a comment."
    checked = subprocess.run(["nginx", "-t", "-c", path], stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    assert checked.returncode == 0, f"Invalid Nginx configuration:\n{checked.stderr}"


def test_randomized_recursive_adversarial_corpus():
    token = secrets.token_hex(20).encode()
    corpus = {
        "root.log": (
            b"[2026-07-01 01:02:03] INFO clean-" + token + b"\n"
            b"clean continuation " + token + b"\n"
            b"[2026-07-01 01:02:04] ERROR beginning\n"
            b"trace line\n[SPAM-MODULE] generated-" + token + b"\n"
            b"[2026-07-01 01:02:05] INFO survived\n"
        ),
        "one/two/mixed.log": (
            b"[1999-12-31 23:59:59] clean nested " + token + b"\n"
            b"[SPAM-MODULEX] is not the exact payload\n"
            b"[2000-01-01 00:00:00] remove this\n"
            b"continuation [SPAM-MODULE] " + token + b"\n"
            b"[2000-01-01 00:00:01] final clean without trailing newline " + token
        ),
        "one/all-clean.log": (
            b"[2024-02-29 10:11:12] alpha " + token + b"\nline two\n"
            b"[2024-02-29 10:11:13] omega " + token + b"\n"
        ),
    }

    with tempfile.TemporaryDirectory() as td:
        inp = Path(td) / ("input-" + secrets.token_hex(6))
        out = Path(td) / ("output-" + secrets.token_hex(6))
        inp.mkdir()
        for rel, data in corpus.items():
            path = inp / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (inp / "one/ignore.txt").write_bytes(b"[2026-01-01 00:00:00] [SPAM-MODULE]\n")

        result = run_binary(inp, out)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        expected_paths = set(corpus)
        actual_paths = {str(p.relative_to(out)) for p in out.rglob("*") if p.is_file()}
        assert actual_paths == expected_paths, \
            f"Unexpected or missing output files: expected {expected_paths}, got {actual_paths}"
        for rel, data in corpus.items():
            actual = (out / rel).read_bytes()
            assert actual == expected_output(data), f"Incorrect sanitization for {rel}"


def test_atomic_replacement_uses_rename():
    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    IN_MOVED_TO = 0x00000080

    token = secrets.token_hex(16).encode()
    data = b"[2026-08-09 10:11:12] large clean " + token + b"\n" + \
           (b"continuation-" + token + b"\n") * 180000

    with tempfile.TemporaryDirectory() as td:
        inp = Path(td) / "in"
        out = Path(td) / "out"
        inp.mkdir()
        out.mkdir()
        (inp / "atomic.log").write_bytes(data)
        (out / "atomic.log").write_bytes(b"old-complete-file\n")

        fd = inotify_init1(os.O_NONBLOCK)
        assert fd >= 0, "Unable to initialize filesystem event monitoring."
        try:
            wd = inotify_add_watch(fd, os.fsencode(out), IN_MOVED_TO)
            assert wd >= 0, "Unable to watch sanitizer output directory."
            result = run_binary(inp, out, timeout=30)
            assert result.returncode == 0, result.stderr.decode(errors="replace")

            events = b""
            while True:
                try:
                    events += os.read(fd, 65536)
                except BlockingIOError:
                    break
            moved_names = []
            offset = 0
            while offset + 16 <= len(events):
                _, mask, _, length = struct.unpack_from("iIII", events, offset)
                name = events[offset + 16:offset + 16 + length].split(b"\0", 1)[0]
                if mask & IN_MOVED_TO:
                    moved_names.append(os.fsdecode(name))
                offset += 16 + length
            assert "atomic.log" in moved_names, \
                "Final output was not atomically installed with rename."
            assert (out / "atomic.log").read_bytes() == data
            assert not any(p.name.endswith(".tmp") for p in out.iterdir()), \
                "Temporary output files were left behind."
        finally:
            os.close(fd)


def test_actual_raw_to_processed_end_to_end_run():
    unique = "verification-" + secrets.token_hex(10)
    raw_dir = Path("/home/user/logs/raw") / unique
    processed_file = Path("/home/user/logs/processed") / unique / "manual.log"
    raw_dir.mkdir(parents=True)
    token = secrets.token_hex(16).encode()
    data = (b"[2026-09-01 01:01:01] keep " + token + b"\n"
            b"[2026-09-01 01:01:02] discard\ncontinuation [SPAM-MODULE]\n"
            b"[2026-09-01 01:01:03] keep-last " + token + b"\n")
    (raw_dir / "manual.log").write_bytes(data)

    result = run_binary("/home/user/logs/raw", "/home/user/logs/processed", timeout=20)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert processed_file.is_file(), "Raw-to-processed end-to-end run produced no output."
    actual = processed_file.read_bytes()
    assert actual == expected_output(data)
    assert b"[SPAM-MODULE]" not in actual, "Processed logs still expose spam to the shipper."


def test_restart_script_and_forwarded_header_end_to_end():
    server_code = r'''
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        value = self.headers.get("X-Sanitizer-Enabled", "")
        body = value.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
'''
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    backend = subprocess.Popen(["python3", "-c", server_code],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(0.3)
        assert backend.poll() is None, "Could not start the backend header probe on port 5000."
        restarted = subprocess.run(["/home/user/app/restart_services.sh"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, timeout=15)
        assert restarted.returncode == 0, \
            f"Service restart failed:\n{restarted.stdout}\n{restarted.stderr}"

        response = None
        last_error = None
        for _ in range(30):
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1) as r:
                    response = r.read().decode().strip()
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert response is not None, f"Restarted Nginx did not proxy to the backend: {last_error}"
        assert response.lower() == "true", \
            f"Backend received X-Sanitizer-Enabled={response!r}, expected 'true'."
    finally:
        subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
