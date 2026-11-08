#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.request

import yaml

HOME = "/home/user"
SERVICES = HOME + "/services"
ARCHIVE = SERVICES + "/nginx/html/docs.tar"
OUTPUT = HOME + "/valid_files.txt"
SOURCE = HOME + "/indexer.c"
BINARY = "/tmp/agent_indexer"


def http_get(url, attempts=20):
    last = None
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return response.status, response.headers, response.read()
        except Exception as exc:
            last = exc
            time.sleep(0.25)
    raise AssertionError(f"Could not fetch {url}: {last}")


def redis_command(*parts):
    payload = f"*{len(parts)}\r\n".encode()
    for part in parts:
        value = str(part).encode()
        payload += f"${len(value)}\r\n".encode() + value + b"\r\n"
    with socket.create_connection(("127.0.0.1", 6379), timeout=3) as sock:
        sock.sendall(payload)
        return sock.recv(4096)


def make_archive(entries, corrupt_checksum=False):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tar_path = tmp.name
    try:
        with tarfile.open(tar_path, "w", format=tarfile.USTAR_FORMAT) as archive:
            for name, data in entries:
                info = tarfile.TarInfo(name=name)
                info.size = len(data)
                info.mode = 0o644
                info.mtime = 1700000000
                import io
                archive.addfile(info, io.BytesIO(data))

            for name, target in [
                ("api/latest", "../api/latest"),
                ("recursive", "recursive"),
                ("guide/current", "../guide/current"),
            ]:
                info = tarfile.TarInfo(name=name)
                info.type = tarfile.SYMTYPE
                info.linkname = target
                info.mode = 0o777
                info.mtime = 1700000000
                archive.addfile(info)

        with open(tar_path, "rb") as handle:
            tar_data = handle.read()
        assert len(tar_data) % 512 == 0

        checksum = bytearray(32)
        for block_start in range(0, len(tar_data), 512):
            block = tar_data[block_start:block_start + 512]
            for index, value in enumerate(block):
                checksum[index % 32] ^= value
        if corrupt_checksum:
            checksum[0] ^= 0x80
        return tar_data + bytes(checksum)
    finally:
        os.unlink(tar_path)


def install_archive(data):
    os.makedirs(os.path.dirname(ARCHIVE), exist_ok=True)
    temp_path = ARCHIVE + ".verifier-tmp"
    with open(temp_path, "wb") as handle:
        handle.write(data)
    os.replace(temp_path, ARCHIVE)


def flush_redis():
    reply = redis_command("FLUSHALL")
    assert reply.startswith(b"+OK"), f"Redis FLUSHALL failed: {reply!r}"


def run_indexer(timeout=20):
    return subprocess.run(
        [BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, text=True
    )


def read_output():
    if not os.path.exists(OUTPUT):
        return []
    with open(OUTPUT, "r") as handle:
        return [line.strip() for line in handle if line.strip()]


def assert_f1(agent_lines, truth_lines):
    set_agent = set(agent_lines)
    set_truth = set(truth_lines)
    if len(set_agent) == 0 and len(set_truth) == 0:
        f1 = 1.0
    elif len(set_agent) + len(set_truth) == 0:
        f1 = 0.0
    else:
        f1 = len(set_agent & set_truth) / (0.5 * (len(set_agent) + len(set_truth)))
    assert f1 >= 0.95, (
        f"F1 score {f1:.4f} is below the 0.95 threshold. "
        f"Expected files: {truth_lines}, but got: {agent_lines}"
    )


def test_complete_indexing_workflow():
    compose_file = SERVICES + "/docker-compose.yml"
    env_file = SERVICES + "/flask_app/.env"
    assert os.path.exists(compose_file), f"{compose_file} is missing"
    assert os.path.exists(env_file), f"{env_file} is missing"

    with open(env_file, "r") as handle:
        env_content = handle.read()

    # Preserve the original service assertions.
    assert (
        "REDIS_URL=redis://localhost:6379" in env_content
        or "REDIS_URL=redis://redis:6379" in env_content
        or "6379" in env_content
    ), "Flask .env does not seem to configure Redis properly"
    assert "8080" in env_content, "Flask .env does not seem to configure UPSTREAM_URL properly"

    with open(compose_file, "r") as handle:
        compose = yaml.safe_load(handle)
    service_defs = compose.get("services", {})
    for name in ("nginx", "flask", "redis"):
        assert name in service_defs, f"Compose service {name!r} is missing"

    required_ports = {
        "nginx": (8080, 8080),
        "flask": (5000, 5000),
        "redis": (6379, 6379),
    }
    for name, (published, target) in required_ports.items():
        rendered = [str(value) for value in service_defs[name].get("ports", [])]
        assert any(re.fullmatch(rf"(?:127\.0\.0\.1:)?{published}:{target}(?:/(?:tcp|udp))?", value) for value in rendered), (
            f"Service {name} must publish {published}:{target}; found {rendered}"
        )

    assert redis_command("PING").startswith(b"+PONG"), "Redis is not running on port 6379"

    token = secrets.token_hex(8)
    names = [
        f"index-{token}.html",
        f"api/v1/intro-{token}.md",
        f"api/v1/auth-{token}.md",
        f"tutorials/basics-{token}.html",
        f"deep/a/b/reference-{token}.txt",
        f"assets/image-{token}.dat",
        f"./landing-{token}.html",
        f"guide/../canonical-{token}.md",
    ]
    entries = [(name, ("content:" + name).encode()) for name in names]
    truth_lines = sorted({"/" + os.path.normpath(name).lstrip("/") for name in names})

    good_archive = make_archive(entries)
    bad_archive = make_archive(entries, corrupt_checksum=True)
    install_archive(good_archive)
    flush_redis()

    status, _, nginx_body = http_get("http://127.0.0.1:8080/docs.tar")
    assert status == 200 and nginx_body == good_archive, "NGINX is not serving the current archive on port 8080"
    status, flask_headers, flask_body = http_get("http://127.0.0.1:5000/docs.tar")
    assert status == 200 and flask_body == good_archive, "Flask is not proxying NGINX on port 5000"

    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), "The C indexer source is missing or invalid"
    compile_result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY, "-lcurl"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_result.returncode == 0, f"indexer.c did not compile:\n{compile_result.stderr}"

    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = run_indexer()
    assert result.returncode == 0, f"Indexer failed on a valid archive:\n{result.stderr}"
    assert os.path.exists(OUTPUT), f"File {OUTPUT} not found. The C program must write to this file."
    assert_f1(read_output(), truth_lines)

    # A changed, invalid checksum must not be indexed successfully.
    install_archive(bad_archive)
    flush_redis()
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    bad_result = run_indexer()
    bad_lines = read_output()
    assert bad_result.returncode != 0 or not (set(bad_lines) & set(truth_lines)), (
        "The indexer accepted an archive whose appended checksum was corrupted"
    )

    # Restore the valid input and require the final artifact to be produced by C again.
    install_archive(good_archive)
    flush_redis()
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    final_result = run_indexer()
    assert final_result.returncode == 0, f"Indexer failed after restoring the valid archive:\n{final_result.stderr}"
    assert_f1(read_output(), truth_lines)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
