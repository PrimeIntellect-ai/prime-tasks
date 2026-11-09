#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import time
import uuid
import signal
import socket
import shutil
import tempfile
import threading
import subprocess
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest


def get_actual_frame_count(video_path):
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-count_frames",
        "-show_entries", "stream=nb_read_frames",
        "-of", "default=nokey=1:noprint_wrappers=1",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip().isdigit():
        return int(result.stdout.strip())
    return 144


def test_video_artifact_processing():
    frame_count_file = "/home/user/frame_count.txt"
    assert os.path.isfile(frame_count_file), f"Missing file: {frame_count_file}"

    expected_frames = get_actual_frame_count("/app/security_cam.mp4")
    with open(frame_count_file, "r") as f:
        content = f.read().strip()

    assert content == str(expected_frames), f"Expected frame count {expected_frames}, but got {content}"


def test_environment_variables_setup():
    profile_path = "/home/user/.profile"
    assert os.path.isfile(profile_path), f"Missing file: {profile_path}"

    expected_frames = get_actual_frame_count("/app/security_cam.mp4")
    with open(profile_path, "r") as f:
        content = f.read()

    assert "export PROXY_UPSTREAM=127.0.0.1:8080" in content or 'export PROXY_UPSTREAM="127.0.0.1:8080"' in content, \
        "PROXY_UPSTREAM variable not correctly exported in .profile"

    expected_export = f"export VIDEO_PROCESSED_COUNT={expected_frames}"
    assert expected_export in content or f'export VIDEO_PROCESSED_COUNT="{expected_frames}"' in content, \
        f"VIDEO_PROCESSED_COUNT variable not correctly exported in .profile. Expected to find: {expected_export}"


def test_adversarial_payload_sanitizer():
    script_path = "/home/user/filter_payloads.py"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"

    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"

    # Preserve the original fixed-corpus assertions.
    with tempfile.TemporaryDirectory() as tmp_clean_out:
        result = subprocess.run(["python3", script_path, clean_corpus_dir, tmp_clean_out], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on clean corpus: {result.stderr}"

        expected_clean_files = set(os.listdir(clean_corpus_dir))
        actual_clean_files = set(os.listdir(tmp_clean_out))
        missing_clean = expected_clean_files - actual_clean_files
        assert not missing_clean, f"{len(missing_clean)} of {len(expected_clean_files)} clean files modified/rejected: {', '.join(missing_clean)}"

        for name in expected_clean_files:
            with open(os.path.join(clean_corpus_dir, name), "r") as src, open(os.path.join(tmp_clean_out, name), "r") as dst:
                assert src.read() == dst.read(), f"Clean file {name} was modified during copy"

    with tempfile.TemporaryDirectory() as tmp_evil_out:
        result = subprocess.run(["python3", script_path, evil_corpus_dir, tmp_evil_out], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on evil corpus: {result.stderr}"
        actual_evil_files = set(os.listdir(tmp_evil_out))
        assert not actual_evil_files, f"{len(actual_evil_files)} of {len(os.listdir(evil_corpus_dir))} evil files bypassed: {', '.join(actual_evil_files)}"

    # Exercise a fresh mixed corpus with unpredictable paths, names, and contents.
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix=f"payload-input-{token}-") as input_dir, \
         tempfile.TemporaryDirectory(prefix=f"payload-output-{token}-") as output_dir:
        payloads = {
            f"camera-{uuid.uuid4().hex}.json": {
                "service": f"camera-{token}",
                "mount_path": f"/srv/video/{token}",
                "note": "../ in an unrelated value must not cause rejection",
            },
            f"cache-{uuid.uuid4().hex}.json": {
                "mount_path": f"/tmp/{token}/..safe",
                "service": "cache",
            },
            f"escape-{uuid.uuid4().hex}.json": {
                "service": "intruder",
                "mount_path": f"/srv/{token}/../private",
            },
            f"relative-{uuid.uuid4().hex}.json": {
                "mount_path": f"../{token}/secret",
                "service": "intruder-two",
            },
        }
        expected_bytes = {}
        for index, (name, data) in enumerate(payloads.items()):
            raw = (json.dumps(data, ensure_ascii=False, indent=(2 if index % 2 else None)) + "\n").encode("utf-8")
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(raw)
            if "../" not in data["mount_path"]:
                expected_bytes[name] = raw

        with open(os.path.join(input_dir, f"ignored-{uuid.uuid4().hex}.txt"), "w") as f:
            f.write('{"mount_path": "/must/not/be/copied"}\n')

        result = subprocess.run(["python3", script_path, input_dir, output_dir], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on generated mixed corpus: {result.stderr}"
        assert set(os.listdir(output_dir)) == set(expected_bytes), \
            "Sanitizer did not copy exactly the generated clean JSON files"
        for name, raw in expected_bytes.items():
            with open(os.path.join(output_dir, name), "rb") as f:
                assert f.read() == raw, f"Generated clean file {name} was modified"


def _provided_payload_expectations():
    expected = {}
    for directory in ("/app/corpus/clean", "/app/corpus/evil"):
        for name in os.listdir(directory):
            if not name.endswith(".json"):
                continue
            path = os.path.join(directory, name)
            with open(path, "rb") as f:
                raw = f.read()
            data = json.loads(raw)
            if "../" not in data["mount_path"]:
                assert name not in expected, f"Duplicate provided payload filename: {name}"
                expected[name] = (raw, data["mount_path"])
    return expected


def test_mount_fstab_configuration():
    fstab_path = "/home/user/container_fstab"
    assert os.path.isfile(fstab_path), f"Missing file: {fstab_path}"

    # Preserve the original expected-line assertions.
    clean_corpus_dir = "/app/corpus/clean"
    expected_mounts = []
    if os.path.isdir(clean_corpus_dir):
        for name in os.listdir(clean_corpus_dir):
            if name.endswith(".json"):
                with open(os.path.join(clean_corpus_dir, name), "r") as fp:
                    data = json.load(fp)
                    if "mount_path" in data:
                        expected_mounts.append(data["mount_path"])

    with open(fstab_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    for mount_path in expected_mounts:
        expected_line = f"tmpfs {mount_path} tmpfs defaults 0 0"
        assert expected_line in lines, f"Missing expected fstab entry: {expected_line}"

    # Verify the persisted accepted-payload pipeline and reject extra fstab entries.
    accepted_dir = "/home/user/accepted_payloads"
    assert os.path.isdir(accepted_dir), f"Missing directory: {accepted_dir}"
    expected_payloads = _provided_payload_expectations()
    actual_names = set(os.listdir(accepted_dir))
    assert actual_names == set(expected_payloads), \
        f"accepted_payloads does not contain exactly the provided clean payloads: {actual_names}"

    for name, (expected_raw, _) in expected_payloads.items():
        accepted_path = os.path.join(accepted_dir, name)
        assert os.path.isfile(accepted_path), f"Accepted payload is not a file: {accepted_path}"
        with open(accepted_path, "rb") as f:
            assert f.read() == expected_raw, f"Accepted payload {name} was modified"

    exact_expected_lines = Counter(
        f"tmpfs {mount_path} tmpfs defaults 0 0"
        for _, mount_path in expected_payloads.values()
    )
    assert Counter(lines) == exact_expected_lines, \
        f"container_fstab must contain exactly one entry per accepted payload; got {lines}"


class _ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


class _UpstreamHandler(BaseHTTPRequestHandler):
    records = []

    def do_GET(self):
        type(self).records.append((self.path, dict(self.headers.items())))
        body = ("UPSTREAM:" + self.path).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def _request(path, header_value=None):
    headers = {}
    if header_value is not None:
        headers["X-Microservice"] = header_value
    request = Request(f"http://127.0.0.1:9090{path}", headers=headers)
    try:
        with urlopen(request, timeout=3) as response:
            return response.status, response.read()
    except HTTPError as error:
        return error.code, error.read()


def _wait_for_nginx(process, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read() if process.stderr else ""
            pytest.fail(f"Nginx exited before serving requests: {stderr}")
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("Nginx did not begin listening on port 9090")


def test_nginx_configuration():
    nginx_conf = "/home/user/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Missing file: {nginx_conf}"

    result = subprocess.run(["nginx", "-t", "-c", nginx_conf], capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx configuration failed validation:\n{result.stderr}"

    with open(nginx_conf, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert "9090" in content, "Nginx config does not appear to listen on port 9090"
    assert "proxy_pass http://127.0.0.1:8080" in content or "proxy_pass http://127.0.0.1:8080/" in content, \
        "Nginx config is missing the correct proxy_pass directive"
    assert "403" in content, "Nginx config is missing 403 Forbidden directive for missing/invalid header"
    assert "http_x_microservice" in content.lower() or "http_x_microservice" in content, \
        "Nginx config does not check the X-Microservice header"
    assert "accepted" in content, "Nginx config does not check for the 'accepted' value in the header"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    assert re.search(r"(?m)^\s*daemon\s+off\s*;", uncommented), "Nginx must run with daemon off"
    assert re.search(r"(?m)^\s*pid\s+/home/user/nginx\.pid\s*;", uncommented), \
        "Nginx must use pid /home/user/nginx.pid"

    _UpstreamHandler.records = []
    upstream = _ReusableHTTPServer(("127.0.0.1", 8080), _UpstreamHandler)
    upstream_thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    upstream_thread.start()

    process = subprocess.Popen(
        ["nginx", "-c", nginx_conf],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        _wait_for_nginx(process)
        token = uuid.uuid4().hex

        for path in (f"/verify/{token}?source=edge", f"/another/{uuid.uuid4().hex}"):
            status, body = _request(path, "accepted")
            assert status == 200, f"Accepted request to {path} was not proxied: HTTP {status}"
            assert body == ("UPSTREAM:" + path).encode(), f"Accepted request to {path} did not reach the upstream"

        accepted_count = len(_UpstreamHandler.records)
        for value in (None, "rejected", "Accepted", "accepted-extra"):
            path = f"/blocked/{uuid.uuid4().hex}"
            status, _ = _request(path, value)
            assert status == 403, f"Invalid X-Microservice value {value!r} returned HTTP {status}, not 403"

        time.sleep(0.2)
        assert len(_UpstreamHandler.records) == accepted_count, \
            "A missing or invalid X-Microservice header was forwarded upstream"
    finally:
        upstream.shutdown()
        upstream.server_close()
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
