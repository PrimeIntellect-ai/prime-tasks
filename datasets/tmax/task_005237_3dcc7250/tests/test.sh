#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import http.client
import importlib.machinery
import json
import os
import queue
import re
import secrets
import socketserver
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler

import pytest


def test_part1_vendored_package_installed():
    """Verify the Rust-backed package builds, is globally installed, and handles arbitrary names."""
    try:
        import mobile_asset_builder
    except ImportError:
        pytest.fail("mobile_asset_builder is not installed in the Python environment.")

    try:
        result = mobile_asset_builder.process("test")
        assert result == "test_asset", f"Expected 'test_asset', got '{result}'"
    except Exception as e:
        pytest.fail(f"mobile_asset_builder.process failed: {e}")

    source_dir = "/app/vendored_package/mobile_asset_builder"
    source_file = os.path.join(source_dir, "src", "lib.rs")
    assert os.path.isfile(source_file), "Vendored Rust source is missing."

    build = subprocess.run(
        ["cargo", "check", "--offline"],
        cwd=source_dir,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert build.returncode == 0, f"The repaired Rust source does not compile:\n{build.stdout}\n{build.stderr}"

    names = [
        "asset_" + secrets.token_hex(8),
        "release bundle " + secrets.token_hex(5),
        "移动-" + secrets.token_hex(4),
        "x/y-" + secrets.token_hex(6),
    ]
    probe = r'''
import importlib.metadata
import json
import mobile_asset_builder
import sys
names = json.loads(sys.argv[1])
print(json.dumps({
    "file": mobile_asset_builder.__file__,
    "version": importlib.metadata.version("mobile_asset_builder"),
    "results": [mobile_asset_builder.process(x) for x in names],
}))
'''
    isolated = subprocess.run(
        ["python3", "-I", "-c", probe, json.dumps(names)],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert isolated.returncode == 0, f"Package is not globally importable:\n{isolated.stderr}"
    info = json.loads(isolated.stdout.strip())
    assert info["version"] == "0.1.0"
    assert any(info["file"].endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"Installed module is not a native extension: {info['file']}"
    assert info["results"] == [name + "_asset" for name in names]


def run_sanitizer(script_path, manifest_path):
    return subprocess.run(
        ["python3", script_path, manifest_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_part2_manifest_sanitizer():
    """Verify the sanitizer on both supplied and independently generated manifests."""
    script_path = "/home/user/sanitizer.py"
    assert os.path.isfile(script_path), f"Sanitizer script missing at {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)] if os.path.isdir(clean_dir) else []
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)] if os.path.isdir(evil_dir) else []

    clean_failed = []
    for cf in clean_files:
        if run_sanitizer(script_path, cf) != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        if run_sanitizer(script_path, ef) != 1:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))

    token = secrets.token_hex(10)
    cases = [
        ({"output_dir": f"build/{token}/outputs/"}, 0),
        ({"output_dir": f"../{token}/build/"}, 1),
        ({"output_dir": f"build/{token}/../../release"}, 1),
        ({"output_dir": f"build/..hidden/{token}"}, 0),
        ({"output_dir": f"构建/{token}/输出"}, 0),
        ({"output_dir": f"prefix-{token}/../escape"}, 1),
    ]
    with tempfile.TemporaryDirectory(prefix="manifest-probe-") as td:
        for index, (document, expected) in enumerate(cases):
            path = os.path.join(td, f"{secrets.token_hex(8)}-{index}.dat")
            encoded = base64.b64encode(
                json.dumps(document, ensure_ascii=False).encode("utf-16le")
            )
            with open(path, "wb") as handle:
                handle.write(encoded)
            actual = run_sanitizer(script_path, path)
            assert actual == expected, \
                f"Sanitizer returned {actual}, expected {expected}, for output_dir={document['output_dir']!r}"


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def test_part3_reverse_proxy_config():
    """Verify syntax, placement, and actual proxy/header behavior."""
    config_path = "/home/user/proxy.conf"
    assert os.path.isfile(config_path), f"Nginx config missing at {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    content_without_comments = re.sub(r'#.*', '', content)
    assert re.search(r'listen\s+8080\s*;', content_without_comments), "Missing or incorrect 'listen 8080;' directive."
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:9000/?\s*;', content_without_comments), "Missing or incorrect 'proxy_pass http://127.0.0.1:9000;' directive."
    assert re.search(r'proxy_set_header\s+X-Mobile-Pipeline\s+["\']?secured["\']?\s*;', content_without_comments, re.IGNORECASE), "Missing or incorrect 'proxy_set_header X-Mobile-Pipeline secured;' directive."

    workdir = tempfile.mkdtemp(prefix="nginx-verify-")
    os.makedirs(os.path.join(workdir, "logs"), exist_ok=True)
    selected_config = config_path

    direct_check = subprocess.run(
        ["nginx", "-t", "-c", config_path], text=True, capture_output=True
    )
    if direct_check.returncode != 0:
        # A server block is also a valid include-style Nginx configuration.
        selected_config = os.path.join(workdir, "nginx.conf")
        with open(selected_config, "w") as wrapper:
            wrapper.write(f"events {{}}\nhttp {{ include {config_path}; }}\n")
        wrapped_check = subprocess.run(
            ["nginx", "-t", "-c", selected_config, "-p", workdir],
            text=True,
            capture_output=True,
        )
        assert wrapped_check.returncode == 0, \
            f"Invalid Nginx syntax or directive placement:\n{direct_check.stderr}\n{wrapped_check.stderr}"

    observed = queue.Queue()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            observed.put((self.path, self.headers.get("X-Mobile-Pipeline")))
            body = ("upstream-" + secrets.token_hex(6)).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    upstream = ThreadedTCPServer(("127.0.0.1", 9000), Handler)
    thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    thread.start()
    nginx_proc = None
    try:
        nginx_proc = subprocess.Popen(
            ["nginx", "-c", selected_config, "-p", workdir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        paths = ["/", "/artifacts/" + secrets.token_hex(8), "/nested/build/file.bin"]
        for path in paths:
            deadline = time.time() + 8
            last_error = None
            while time.time() < deadline:
                try:
                    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
                    conn.request("GET", path)
                    response = conn.getresponse()
                    response.read()
                    conn.close()
                    assert response.status == 200
                    break
                except (OSError, http.client.HTTPException) as exc:
                    last_error = exc
                    time.sleep(0.1)
            else:
                pytest.fail(f"Nginx did not proxy {path!r} on port 8080: {last_error}")

            seen_path, seen_header = observed.get(timeout=3)
            assert seen_path == path, f"Request path was not proxied unchanged: {seen_path!r}"
            assert seen_header == "secured", \
                f"Upstream received X-Mobile-Pipeline={seen_header!r}, expected 'secured'"
    finally:
        subprocess.run(
            ["nginx", "-c", selected_config, "-p", workdir, "-s", "stop"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if nginx_proc is not None and nginx_proc.poll() is None:
            nginx_proc.terminate()
            try:
                nginx_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                nginx_proc.kill()
        upstream.shutdown()
        upstream.server_close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
