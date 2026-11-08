#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import signal
import socket
import subprocess
import uuid
from pathlib import Path

import pytest


def request(payload):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3.0)
            s.connect(("127.0.0.1", 8888))
            s.sendall(payload)
            response = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            return response
    except Exception as e:
        pytest.fail(f"Failed to communicate with TCP server on port 8888: {e}")


def compiled(data):
    proc = subprocess.run(
        ["/app/tm_compiler"], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert proc.returncode == 0, f"tm_compiler failed: {proc.stderr!r}"
    return proc.stdout


def test_anomalies_file():
    path = "/home/user/anomalies.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 1, f"Expected exactly 1 anomaly line, found {len(lines)}"
    assert lines[0] == "2023-10-04T16,12", f"Incorrect anomaly data: {lines[0]}"


def test_clean_tm_file():
    path = "/home/user/clean_tm.csv"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in clean_tm.csv, found {len(lines)}"

    md5_hello = hashlib.md5(b"Hello World").hexdigest()
    md5_save = hashlib.md5(b"Save").hexdigest()
    expected_hello = f"{md5_hello},Salut tout le monde"
    expected_save = f"{md5_save},Enregistrer"

    assert expected_hello in lines, "Missing or incorrect entry for 'Hello World' in clean_tm.csv"
    assert expected_save in lines, "Missing or incorrect entry for 'Save' in clean_tm.csv"


def test_pack_bin_file():
    path = "/home/user/pack.bin"
    assert os.path.exists(path), f"File {path} does not exist."
    data = Path(path).read_bytes()
    assert data.startswith(b"TMPK"), "pack.bin does not start with the TMPK magic header."
    assert len(data) > 4, "pack.bin contains only the magic header, no data."

    clean = Path("/home/user/clean_tm.csv").read_bytes()
    assert data == compiled(clean), "pack.bin is not the exact output of /app/tm_compiler for clean_tm.csv"


def test_tcp_get_anomalies():
    response = request(b"GET_ANOMALIES\n")
    assert b"2023-10-04T16,12" in response, f"TCP server did not return correct anomalies data: {response!r}"
    assert response == Path("/home/user/anomalies.txt").read_bytes(), \
        "GET_ANOMALIES did not return the exact anomalies.txt contents"


def test_tcp_get_pack():
    response = request(b"GET_PACK\n")
    assert response.startswith(b"TMPK"), "TCP server response is missing the TMPK header."
    assert len(response) > 4, "TCP server returned empty pack data."
    assert response == Path("/home/user/pack.bin").read_bytes(), \
        "GET_PACK did not return the exact pack.bin contents"


def shell_scripts():
    found = []
    excluded = {"l10n_logs.csv", "anomalies.txt", "clean_tm.csv", "pack.bin"}
    for root in (Path("/home/user"), Path("/app"), Path("/tmp"), Path("/root")):
        if not root.exists():
            continue
        try:
            paths = root.rglob("*")
            for path in paths:
                try:
                    if not path.is_file() or path.name in excluded:
                        continue
                    if path.stat().st_size > 512000:
                        continue
                    head = path.read_bytes()[:256]
                    if path.suffix == ".sh" or head.startswith(b"#!/bin/bash") or head.startswith(b"#!/usr/bin/env bash") or head.startswith(b"#!/bin/sh"):
                        if path != Path("/tmp/test_final_state.py"):
                            found.append(path)
                except (OSError, PermissionError):
                    pass
        except (OSError, PermissionError):
            pass
    return sorted(set(found), key=lambda p: str(p))


def run_script(path):
    proc = subprocess.Popen(
        ["bash", str(path)], cwd=str(path.parent), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, start_new_session=True
    )
    try:
        out, err = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            out, err = proc.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            out, err = proc.communicate()
    return out + b"\n" + err


def contains_masked_probe(blob, marker, ip, email, domain):
    for line in blob.splitlines():
        if (marker in line and b"0.0.0.0" in line and
                (b"***@" + domain) in line and ip not in line and email not in line):
            return True
    return False


def collect_user_files():
    blobs = []
    for path in Path("/home/user").rglob("*"):
        try:
            if path.is_file() and path.stat().st_size <= 2_000_000:
                blobs.append(path.read_bytes())
        except (OSError, PermissionError):
            pass
    return blobs


def test_z_pipeline_on_unseen_input_and_pii_masking():
    scripts = shell_scripts()
    assert scripts, "No Bash processing/server script was found"

    token = uuid.uuid4().hex.encode("ascii")
    marker = b"PII_PROBE_" + token
    domain = b"probe-" + token + b".example"
    email = b"private.user@" + domain
    octet = 20 + (token[0] % 180)
    ip = f"198.51.100.{octet}".encode("ascii")

    challenge = []
    for minute in range(11):
        challenge.append(
            b"2042-07-19T09:%02d:00Z | " % minute + ip + b" | " + email +
            b" | MISSING | " + marker + b"_MISS_%02d | \n" % minute
        )
    challenge.extend([
        b"2042-07-19T10:05:00Z | " + ip + b" | " + email + b" | UPDATE | " + marker + b"_DUP | Old target\n",
        b"2042-07-19T12:05:00Z | " + ip + b" | " + email + b" | UPDATE | " + marker + b"_DUP | New target\n",
        b"2042-07-19T11:05:00Z | " + ip + b" | " + email + b" | UPDATE | " + marker + b"_OTHER | Other target\n",
        b"2042-07-19T13:05:00Z | " + ip + b" | " + email + b" | VIEW | " + marker + b"_VIEW | Viewed target\n",
    ])

    log = Path("/home/user/l10n_logs.csv")
    with log.open("ab") as f:
        if log.stat().st_size and not log.read_bytes().endswith(b"\n"):
            f.write(b"\n")
        for row in challenge:
            f.write(row)

    expected_clean = {
        hashlib.md5(b"Hello World").hexdigest() + ",Salut tout le monde",
        hashlib.md5(b"Save").hexdigest() + ",Enregistrer",
        hashlib.md5(marker + b"_DUP").hexdigest() + ",New target",
        hashlib.md5(marker + b"_OTHER").hexdigest() + ",Other target",
    }
    expected_anomalies = {"2023-10-04T16,12", "2042-07-19T09,11"}

    observed = []
    succeeded = False
    for script in scripts[:30]:
        observed.append(run_script(script))
        try:
            anomaly_lines = {
                x.strip() for x in Path("/home/user/anomalies.txt").read_text().splitlines() if x.strip()
            }
            clean_lines = {
                x.strip() for x in Path("/home/user/clean_tm.csv").read_text().splitlines() if x.strip()
            }
            pack = Path("/home/user/pack.bin").read_bytes()
            clean_bytes = Path("/home/user/clean_tm.csv").read_bytes()
            if anomaly_lines == expected_anomalies and clean_lines == expected_clean and pack == compiled(clean_bytes):
                succeeded = True
                break
        except (OSError, UnicodeError):
            pass

    assert succeeded, "The Bash pipeline did not correctly process unseen anomaly and deduplication inputs or compile their result"

    observed.extend(collect_user_files())
    assert any(contains_masked_probe(blob, marker, ip, email, domain) for blob in observed), \
        "No pipeline output demonstrated regex-style masking of the unseen IP address and email"

    assert request(b"GET_ANOMALIES\n") == Path("/home/user/anomalies.txt").read_bytes(), \
        "The server returned canned anomaly data instead of the newly generated file"
    assert request(b"GET_PACK\n") == Path("/home/user/pack.bin").read_bytes(), \
        "The server returned fabricated pack data instead of the newly generated pack.bin"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
