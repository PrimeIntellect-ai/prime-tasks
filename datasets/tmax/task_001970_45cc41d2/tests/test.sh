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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import requests


def test_http_server_artifacts():
    url = "http://127.0.0.1:8080/artifacts"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the server at {url}: {e}"

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"

    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"

    expected_artifacts = [
        {"id": "1", "name": "sys-core.tar.gz", "size": 450},
        {"id": "3", "name": "net-utils.tgz", "size": 890},
        {"id": "5", "name": "auth-lib.tar.gz", "size": 120}
    ]

    assert "artifacts" in data, "JSON response missing 'artifacts' key"
    assert data["artifacts"] == expected_artifacts, f"Expected artifacts {expected_artifacts}, got {data['artifacts']}"


def listening_pids_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state = fields[1], fields[3]
            if state != "0A":
                continue
            address, port = local.rsplit(":", 1)
            if port.upper() != "1F90":
                continue
            # 127.0.0.1 is represented as 0100007F in /proc/net/tcp.
            if table.endswith("tcp") and address.upper() != "0100007F":
                continue
            inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(proc.name))
                break
    return pids


def test_listener_is_a_go_server():
    pids = listening_pids_8080()
    assert pids, "No process is listening exactly on 127.0.0.1:8080"
    details = []
    for pid in pids:
        result = subprocess.run(
            ["go", "version", "-m", f"/proc/{pid}/exe"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=5,
        )
        details.append(result.stdout)
        if result.returncode == 0 and "go1" in result.stdout:
            return
    assert False, "The process serving 127.0.0.1:8080 is not a Go executable: " + repr(details)


def encode_rle_xor(raw, key=137):
    out = bytearray()
    i = 0
    while i < len(raw):
        count = 1
        while i + count < len(raw) and raw[i + count] == raw[i] and count < 255:
            count += 1
        out.append(count ^ key)
        out.append(raw[i] ^ key)
        i += count
    return bytes(out)


def find_go_sources():
    roots = [Path(p) for p in ("/app", "/home", "/root", "/tmp", "/workspace") if Path(p).exists()]
    found = []
    for root in roots:
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "node_modules", "vendor", "pkg"}]
            if current.startswith("/tmp/go-build"):
                dirs[:] = []
                continue
            for name in files:
                if name.endswith(".go") and not name.endswith("_test.go"):
                    found.append(Path(current) / name)
                    if len(found) >= 100:
                        return found
    return found


def decoder_payloads():
    token = secrets.token_hex(8)
    texts = [
        f"id,name,size\n71,{token}.tar,999\n72,zzzz-{token}.bin,1000\n",
        f"id,name,size\n8,aaaaabbbbb-{token},7\n9,q,12345\n",
    ]
    return [(encode_rle_xor(t.encode("ascii")), t.encode("ascii")) for t in texts]


def binary_decodes(binary, payloads):
    for encoded, expected in payloads:
        try:
            run = subprocess.run(
                [str(binary)],
                input=encoded,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=4,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        if run.returncode != 0 or run.stdout != expected:
            return False
    return True


def test_go_decoder_on_derived_inputs():
    sources = find_go_sources()
    assert sources, "No submitted Go source code was found"
    payloads = decoder_payloads()

    candidates = []
    for source in sources:
        candidates.append((source.parent, [source.name]))
    for directory in sorted({p.parent for p in sources}, key=str):
        names = sorted(p.name for p in sources if p.parent == directory)
        if len(names) > 1:
            candidates.append((directory, names))

    with tempfile.TemporaryDirectory(prefix="verify-go-") as td:
        for index, (cwd, names) in enumerate(candidates):
            binary = Path(td) / f"candidate-{index}"
            env = os.environ.copy()
            env["GO111MODULE"] = "off"
            try:
                built = subprocess.run(
                    ["go", "build", "-o", str(binary), *names],
                    cwd=str(cwd),
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if built.returncode == 0 and binary_decodes(binary, payloads):
                return

    assert False, "No submitted Go program correctly decoded fresh XOR/RLE inputs from stdin to stdout"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
