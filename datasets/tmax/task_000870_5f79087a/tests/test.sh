#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import os
import py_compile
import re
import subprocess
import tempfile
import uuid

import pytest
import requests
from elftools.elf.elffile import ELFFile


def test_proxy_metric_threshold():
    """
    Runs the verifier script /app/verify.py and asserts that the final score
    meets the threshold of >= 0.95.
    """
    cmd = ["python3", "/app/verify.py"]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"verify.py execution failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    output = result.stdout.strip()

    # Extract floating point numbers from the output (e.g., 0.95, 1.0)
    matches = re.findall(r"0\.\d+|1\.0|\d+\.\d+", output)
    assert matches, f"Could not find a numeric score in verify.py output.\nOutput was:\n{output}"

    # The final score is typically the last number printed
    score = float(matches[-1])

    assert score >= 0.95, f"Metric score {score} is below the required threshold of 0.95.\nOutput was:\n{output}"


def listener_processes(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    with open(f"/proc/{pid}/cmdline", "rb") as f:
                        owners.append(f.read().replace(b"\0", b" ").decode(errors="replace"))
                    break
        except OSError:
            pass
    return owners


def expected_redaction(original):
    with tempfile.NamedTemporaryFile(suffix=".elf") as f:
        f.write(original)
        f.flush()
        with open(f.name, "rb") as elf_stream:
            elf = ELFFile(elf_stream)
            section = elf.get_section_by_name(".rodata")
            assert section is not None, "Upstream ELF has no .rodata section"
            offset = section["sh_offset"]
            size = section["sh_size"]

    result = bytearray(original)
    rodata = original[offset:offset + size]
    email_pattern = re.compile(rb"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}")
    matches = list(email_pattern.finditer(rodata))
    assert matches, "Test fixture unexpectedly contains no email in .rodata"
    for match in matches:
        start = offset + match.start()
        end = offset + match.end()
        result[start:end] = b"*" * (end - start)
    return bytes(result), [m.group(0) for m in matches]


def test_dynamic_binaries_match_upstream_with_only_rodata_emails_redacted():
    proxy_path = "/home/user/proxy.py"
    assert os.path.isfile(proxy_path), f"Missing required proxy artifact: {proxy_path}"
    py_compile.compile(proxy_path, doraise=True)

    owners = listener_processes(8000)
    assert owners, "No process is listening on port 8000"
    assert any("proxy.py" in cmd for cmd in owners), f"Port 8000 is not served by proxy.py; listener commands: {owners}"

    # Runtime-random IDs of varying lengths prevent a fixed response corpus from passing.
    token = uuid.uuid4().hex
    ids = [f"dyn_{token[:8]}", f"dynamic_{token[:19]}", f"audit_{token}"]

    for idx in ids:
        user_email = f"user_{uuid.uuid4().hex}@test.com"

        upstream_response = requests.get(
            "http://localhost:8001/fetch", params={"id": idx}, timeout=10
        )
        assert upstream_response.status_code == 200
        upstream_json = upstream_response.json()
        assert upstream_json.get("id") == idx
        upstream = base64.b64decode(upstream_json["payload"], validate=True)
        expected, found_emails = expected_redaction(upstream)
        assert found_emails == [f"target_{idx}@example.com".encode()]

        logs_before_response = requests.get("http://localhost:8002/get_logs", timeout=5)
        assert logs_before_response.status_code == 200
        logs_before = logs_before_response.json()

        proxy_response = requests.get(
            "http://localhost:8000/download",
            params={"id": idx, "user": user_email},
            timeout=10,
        )
        assert proxy_response.status_code == 200
        proxy_json = proxy_response.json()
        assert proxy_json.get("id") == idx, "Proxy returned the wrong response id"
        returned = base64.b64decode(proxy_json["payload"], validate=True)

        assert returned == expected, (
            "Returned ELF differs from the corresponding upstream ELF in bytes other "
            "than the required in-place .rodata email redaction"
        )
        assert len(returned) == len(upstream)

        with tempfile.NamedTemporaryFile(suffix=".elf", delete=False) as f:
            elf_path = f.name
            f.write(returned)
        try:
            os.chmod(elf_path, 0o755)
            readelf = subprocess.run(["readelf", "-S", elf_path], capture_output=True, text=True)
            assert readelf.returncode == 0, readelf.stderr
            executed = subprocess.run([elf_path], capture_output=True, timeout=5)
            assert executed.returncode == 0, executed.stderr.decode(errors="replace")
            expected_stdout = b"*" * len(found_emails[0]) + b"\n"
            assert executed.stdout == expected_stdout
        finally:
            os.unlink(elf_path)

        logs_after_response = requests.get("http://localhost:8002/get_logs", timeout=5)
        assert logs_after_response.status_code == 200
        logs_after = logs_after_response.json()
        assert len(logs_after) == len(logs_before) + 1, "Each download must create exactly one log event"
        expected_hash = hmac.new(b"AUDIT_KEY", user_email.encode(), hashlib.sha256).hexdigest()
        assert logs_after[-1] == {"id": idx, "user_hash": expected_hash}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
