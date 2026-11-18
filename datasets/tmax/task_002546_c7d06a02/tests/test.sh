#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.client
import io
import os
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import time
import zipfile

import pytest
import redis

SANITIZER = "/home/user/sanitizer.py"
NGINX_CONF = "/home/user/app/nginx.conf"
RECEIVER = "/home/user/app/receiver.py"


def test_nginx_configuration():
    assert os.path.isfile(NGINX_CONF), "nginx.conf is missing"
    with open(NGINX_CONF, "r") as f:
        content = f.read()
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000", content) or \
           re.search(r"proxy_pass\s+http://[a-zA-Z0-9_-]+:5000", content) or \
           "5000" in content, "Nginx configuration does not seem to proxy to port 5000"


def test_receiver_configuration():
    assert os.path.isfile(RECEIVER), "receiver.py is missing"
    with open(RECEIVER, "r") as f:
        content = f.read()
    assert "import redis" in content or "from redis" in content, "receiver.py does not import redis"
    assert "lpush" in content, "receiver.py does not use lpush to queue the job"


def wait_port(port, proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            pytest.fail(f"service for port {port} exited early: {out!r} {err!r}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"service did not listen on port {port}")


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            pass


def test_end_to_end_upload_is_proxied_and_queued():
    check = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True)
    assert check.returncode == 0, f"invalid nginx configuration: {check.stdout} {check.stderr}"

    subprocess.run(["pkill", "-f", "gunicorn.*receiver:app"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/app/receiver.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["nginx", "-s", "stop", "-c", NGINX_CONF], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    redis_proc = None
    app_proc = None
    nginx_proc = None
    r = redis.Redis(host="127.0.0.1", port=6379, db=0, socket_timeout=1)
    try:
        try:
            r.ping()
        except Exception:
            redis_proc = subprocess.Popen(
                ["redis-server", "--port", "6379", "--save", "", "--appendonly", "no"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True
            )
            wait_port(6379, redis_proc)
        r.flushdb()

        app_proc = subprocess.Popen(
            ["python3", "-m", "gunicorn", "-b", "127.0.0.1:5000", "receiver:app"],
            cwd="/home/user/app", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True
        )
        wait_port(5000, app_proc)

        nginx_proc = subprocess.Popen(
            ["nginx", "-c", NGINX_CONF, "-g", "daemon off;"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True
        )
        wait_port(8080, nginx_proc)

        filename = f"upload_{secrets.token_hex(10)}.zip"
        payload = os.urandom(257)
        boundary = "----verify" + secrets.token_hex(12)
        body = (
            f"--{boundary}\r\n"
            f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
            "Content-Type: application/zip\r\n\r\n"
        ).encode() + payload + f"\r\n--{boundary}--\r\n".encode()
        conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=10)
        conn.request("POST", "/upload", body=body, headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
        })
        response = conn.getresponse()
        response_body = response.read()
        conn.close()
        assert 200 <= response.status < 300, f"upload failed through nginx: {response.status} {response_body!r}"

        saved = os.path.join("/tmp", filename)
        assert os.path.isfile(saved), "receiver did not save the uploaded file"
        with open(saved, "rb") as f:
            assert f.read() == payload, "saved upload differs from submitted data"

        deadline = time.time() + 5
        list_values = []
        while time.time() < deadline:
            list_values = []
            for key in r.keys("*"):
                if r.type(key) == b"list":
                    list_values.extend(r.lrange(key, 0, -1))
            if list_values:
                break
            time.sleep(0.1)
        assert list_values, "upload did not create a Redis list job"
        assert any(filename.encode() in value for value in list_values), \
            "queued Redis job does not identify the uploaded submission"
    finally:
        stop_process(nginx_proc)
        stop_process(app_proc)
        if redis_proc is not None:
            stop_process(redis_proc)


def run_sanitizer(zip_path, output_dir):
    return subprocess.run(
        ["python3", SANITIZER, zip_path, output_dir],
        capture_output=True, timeout=15
    )


def produced_files(root):
    result = []
    for current, _, files in os.walk(root):
        for name in files:
            result.append(os.path.join(current, name))
    return result


def find_basename(root, name):
    matches = [p for p in produced_files(root) if os.path.basename(p) == name]
    assert len(matches) == 1, f"expected exactly one output named {name}, got {matches}"
    return matches[0]


def zip_bytes(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return buffer.getvalue()


def test_sanitizer_randomized_nested_extraction_and_sanitization():
    assert os.path.isfile(SANITIZER), "sanitizer.py is missing"
    token = secrets.token_hex(8)
    top_md = f"top_{token}.md"
    top_txt = f"notes_{token}.txt"
    nested_md = f"nested_{token}.md"
    deep_txt = f"deep_{token}.txt"

    level2 = zip_bytes({deep_txt: b"deep first\n<script> remove this\ndeep last\n"})
    level1 = zip_bytes({
        nested_md: b"nested safe\nline with <script> must disappear\nnested end\n",
        f"level2_{token}.zip": level2,
    })
    outer = zip_bytes({
        top_md: b"alpha\n<script>bad\nomega\n",
        top_txt: b"one\nremove <script> whole line\ntwo\n",
        f"level1_{token}.zip": level1,
        f"ignored_{token}.bin": os.urandom(37),
    })

    with tempfile.TemporaryDirectory() as temp:
        input_path = os.path.join(temp, f"random_{token}.zip")
        output = os.path.join(temp, "out")
        os.mkdir(output)
        with open(input_path, "wb") as f:
            f.write(outer)
        result = run_sanitizer(input_path, output)
        assert result.returncode == 0, f"safe archive failed: {result.stdout!r} {result.stderr!r}"

        expected = {
            top_md: "alpha\nomega\n",
            os.path.splitext(top_txt)[0] + ".md": "one\ntwo\n",
            nested_md: "nested safe\nnested end\n",
            os.path.splitext(deep_txt)[0] + ".md": "deep first\ndeep last\n",
        }
        for name, content in expected.items():
            path = find_basename(output, name)
            with open(path, "r") as f:
                actual = f.read()
            assert actual == content, f"incorrect sanitized content for {name}: {actual!r}"
        assert not any(path.endswith(".txt") for path in produced_files(output)), \
            ".txt output was not converted to .md"


def make_bad_crc_zip(path):
    name = "crc_" + secrets.token_hex(6) + ".bin"
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr(name, os.urandom(128))
    with zipfile.ZipFile(path, "r") as archive:
        info = archive.getinfo(name)
        data_offset = info.header_offset + 30 + len(info.filename.encode()) + len(info.extra)
    with open(path, "r+b") as f:
        f.seek(data_offset)
        original = f.read(1)
        f.seek(data_offset)
        f.write(bytes([original[0] ^ 0x01]))


@pytest.mark.parametrize("kind", ["invalid", "bad_crc", "oversize", "nested_invalid", "nested_oversize"])
def test_sanitizer_randomized_rejects_unsafe_archives(kind):
    assert os.path.isfile(SANITIZER), "sanitizer.py is missing"
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as temp:
        input_path = os.path.join(temp, f"{token}.zip")
        output = os.path.join(temp, "out")
        os.mkdir(output)
        if kind == "invalid":
            with open(input_path, "wb") as f:
                f.write(os.urandom(211))
        elif kind == "bad_crc":
            make_bad_crc_zip(input_path)
        elif kind == "oversize":
            with zipfile.ZipFile(input_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(f"large_{token}.txt", b"A" * (1024 * 1024 + 1))
        elif kind == "nested_invalid":
            with zipfile.ZipFile(input_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(f"inner_{token}.zip", os.urandom(193))
        else:
            inner = zip_bytes({f"large_{token}.md": b"B" * (1024 * 1024 + 1)})
            with zipfile.ZipFile(input_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(f"inner_{token}.zip", inner)
        result = run_sanitizer(input_path, output)
        assert result.returncode == 1, \
            f"{kind} archive must exit with code 1, got {result.returncode}: {result.stdout!r} {result.stderr!r}"


def test_sanitizer_evil_corpus():
    assert os.path.isfile(SANITIZER), "sanitizer.py is missing"
    evil_dir = "/home/user/corpora/evil"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.zip')]
    bypassed = []
    wrong_exit = []
    for evil_file in evil_files:
        zip_path = os.path.join(evil_dir, evil_file)
        with tempfile.TemporaryDirectory() as temp_out:
            result = run_sanitizer(zip_path, temp_out)
            files = os.listdir(temp_out)
            if result.returncode == 0 and len(files) > 0:
                bypassed.append(evil_file)
            if result.returncode != 1:
                wrong_exit.append(f"{evil_file} ({result.returncode})")
    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}")
    if wrong_exit:
        pytest.fail("evil archives did not exit with code 1: " + ", ".join(wrong_exit))


def test_sanitizer_clean_corpus():
    assert os.path.isfile(SANITIZER), "sanitizer.py is missing"
    clean_dir = "/home/user/corpora/clean"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.zip')]
    modified = []
    for clean_file in clean_files:
        zip_path = os.path.join(clean_dir, clean_file)
        with tempfile.TemporaryDirectory() as temp_out:
            result = run_sanitizer(zip_path, temp_out)
            if result.returncode != 0:
                modified.append(f"{clean_file} (exit code {result.returncode})")
                continue
            files = produced_files(temp_out)
            if not files:
                modified.append(f"{clean_file} (no output produced)")
                continue
            for path in files:
                if path.endswith('.txt'):
                    modified.append(f"{clean_file} (.txt file not converted to .md)")
                    break
                with open(path, "r", errors="ignore") as f:
                    if "<script>" in f.read():
                        modified.append(f"{clean_file} (<script> tag not stripped)")
                        break
    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/failed: {', '.join(modified)}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
