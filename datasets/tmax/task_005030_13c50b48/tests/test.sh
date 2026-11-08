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

cat <<'PY_EOF' > /tmp/verify_archiver.py
import os
import random
import shutil
import signal
import socket
import string
import subprocess
import tarfile
import time

import requests

BIN = "/home/user/app/bin/archiver"
SRC = "/home/user/app/src/archiver.c"
ARCHIVES = "/home/user/archives"
FIXED_ROOT = "/home/user/data/test_vol"


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port(port):
    inodes = listening_inodes(port)
    if not inodes:
        return
    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_inodes(port) and time.time() < deadline:
        time.sleep(0.1)


def start_daemon(path):
    kill_port(9000)
    log = open("/tmp/verifier_archiver_daemon.log", "ab", buffering=0)
    proc = subprocess.Popen([path], stdout=log, stderr=log, cwd="/home/user/app")
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"{path} exited before listening on port 9000")
        if listening_inodes(9000):
            return proc, log
        time.sleep(0.1)
    proc.terminate()
    raise AssertionError(f"{path} did not listen on port 9000")


def stop_daemon(proc, log):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    kill_port(9000)
    if log is not None:
        log.close()


def redis_command(*parts):
    payload = f"*{len(parts)}\r\n".encode()
    for part in parts:
        raw = str(part).encode()
        payload += f"${len(raw)}\r\n".encode() + raw + b"\r\n"
    with socket.create_connection(("127.0.0.1", 6379), timeout=5) as sock:
        sock.sendall(payload)
        data = b""
        while b"\r\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        if data.startswith(b"$"):
            length = int(data.split(b"\r\n", 1)[0][1:])
            while len(data.split(b"\r\n", 1)[1]) < length + 2:
                data += sock.recv(4096)
        return data


def direct_backup(path):
    with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
        sock.settimeout(20)
        sock.sendall(f"BACKUP {path}\n".encode())
        response = b""
        while not response.endswith(b"\n"):
            chunk = sock.recv(1024)
            if not chunk:
                break
            response += chunk
    assert response == b"OK\n", f"Expected exact daemon response b'OK\\n', got {response!r}"


def read_manifest(path):
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8")
    lines = text.splitlines(keepends=True)
    assert all(line.endswith("\n") for line in lines), "Every manifest entry must end in a newline"
    parsed = {}
    for line in lines:
        body = line[:-1]
        assert ":" in body, f"Malformed manifest line: {line!r}"
        rel, size_text = body.rsplit(":", 1)
        assert rel and not rel.startswith("/") and ".." not in rel.split("/"), f"Non-relative manifest path: {rel!r}"
        assert size_text.isdigit(), f"Invalid byte size in manifest line: {line!r}"
        assert rel not in parsed, f"Duplicate manifest path: {rel}"
        parsed[rel] = int(size_text)
    return raw, text, parsed


def normalized_regular_members(tar_path, basename):
    with tarfile.open(tar_path, "r:gz") as archive:
        members = archive.getmembers()
        raw_names = []
        for member in members:
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            assert name and not name.startswith("/") and ".." not in name.split("/"), f"Unsafe tar member: {member.name!r}"
            raw_names.append((member, name.rstrip("/")))

        file_names = [name for member, name in raw_names if member.isfile()]
        prefix = basename + "/"
        if file_names and all(name.startswith(prefix) for name in file_names):
            raw_names = [(member, name[len(prefix):] if name.startswith(prefix) else name) for member, name in raw_names]

        regular = {}
        non_directories = []
        for member, name in raw_names:
            if member.isdir():
                continue
            non_directories.append(name)
            assert member.isfile(), f"Archive contains a symlink or other non-regular entry: {name!r}"
            assert name not in regular, f"Duplicate tar member: {name!r}"
            extracted = archive.extractfile(member)
            assert extracted is not None
            regular[name] = (member.size, extracted.read())
        assert len(non_directories) == len(regular)
        return regular


def assert_archive(root, expected):
    basename = os.path.basename(root.rstrip("/"))
    manifest_path = os.path.join(ARCHIVES, basename + ".manifest")
    tar_path = os.path.join(ARCHIVES, basename + ".tar.gz")
    assert os.path.isfile(manifest_path), f"Manifest file missing at {manifest_path}"
    assert os.path.isfile(tar_path), f"Tarball missing at {tar_path}"

    raw, text, manifest = read_manifest(manifest_path)
    expected_sizes = {name: len(content) for name, content in expected.items()}
    assert manifest == expected_sizes, f"Manifest entries differ: expected {expected_sizes!r}, got {manifest!r}"

    regular = normalized_regular_members(tar_path, basename)
    assert set(regular) == set(expected), f"Tar paths differ: expected {set(expected)!r}, got {set(regular)!r}"
    for name, content in expected.items():
        size, archived_content = regular[name]
        assert size == len(content), f"Wrong tar byte size for {name}"
        assert archived_content == content, f"Wrong archived bytes for {name}"
    return raw, text


def make_dynamic_tree(tag):
    root = f"/home/user/data/verify_{tag}"
    outside = f"/home/user/data/verify_target_{tag}"
    shutil.rmtree(root, ignore_errors=True)
    shutil.rmtree(outside, ignore_errors=True)
    os.makedirs(os.path.join(root, "nested", "deep"))
    os.makedirs(outside)

    expected = {
        "root.bin": b"\x00abc\n",
        "nested/deep/report.txt": b"random-report-" + tag.encode(),
        "nested/data.txt.bait": b"substring names must not fool checks",
        "linked/linked.bin": b"followed symlink bytes\x00\xff",
    }
    for rel, content in list(expected.items())[:3]:
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(content)
    with open(os.path.join(outside, "linked.bin"), "wb") as f:
        f.write(expected["linked/linked.bin"])
    with open(os.path.join(root, "temp.dat"), "wb") as f:
        f.write(b"excluded at root")
    with open(os.path.join(root, "nested", "ignore.log"), "wb") as f:
        f.write(b"excluded when nested")

    os.symlink(outside, os.path.join(root, "linked"))
    os.symlink(root, os.path.join(root, "nested", "deep", "cycle_to_root"))
    os.symlink(os.path.join(root, "nested"), os.path.join(root, "nested", "deep", "cycle_to_parent"))
    return root, outside, expected


def clear_result(root):
    basename = os.path.basename(root.rstrip("/"))
    for suffix in (".manifest", ".tar.gz"):
        try:
            os.unlink(os.path.join(ARCHIVES, basename + suffix))
        except FileNotFoundError:
            pass
    redis_command("DEL", "backup_status:" + basename)


def verify_dynamic(root, expected):
    clear_result(root)
    direct_backup(root)
    assert_archive(root, expected)
    basename = os.path.basename(root.rstrip("/"))
    status = redis_command("GET", "backup_status:" + basename)
    assert status == b"$9\r\nCOMPLETED\r\n", f"Redis status was not exactly COMPLETED: {status!r}"


def verify_fixed_end_to_end():
    clear_result(FIXED_ROOT)
    response = requests.post(
        "http://127.0.0.1:8080/backup",
        headers={"Authorization": "Bearer disk-admin-token-99"},
        data="BACKUP /home/user/data/test_vol\n",
        timeout=20,
    )
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "OK", f"Expected response body 'OK', got {response.text!r}"

    status = redis_command("GET", "backup_status:test_vol")
    assert b"COMPLETED" in status, f"Expected Redis key backup_status:test_vol to be COMPLETED, got {status!r}"
    assert status == b"$9\r\nCOMPLETED\r\n", f"Redis value was not exactly COMPLETED: {status!r}"

    raw, text = assert_archive(FIXED_ROOT, {"data.txt": b"Important data\n"})
    assert "data.txt" in text, "data.txt missing from manifest"
    assert "temp.dat" not in text, "temp.dat should have been excluded but is in manifest"
    assert "ignore.log" not in text, "ignore.log should have been excluded but is in manifest"

    log_path = "/home/user/app/test_run.log"
    assert os.path.exists(log_path), f"Test log file missing at {log_path}"
    assert os.path.isfile(log_path), f"Test log is not a regular file: {log_path}"
    with open(log_path, "rb") as f:
        log_data = f.read()
    assert log_data == raw, "test_run.log must contain the exact manifest output for test_vol"


def main():
    assert os.path.isfile(SRC), f"C source missing at {SRC}"
    assert os.path.isfile(BIN), f"Compiled daemon missing at {BIN}"
    assert os.access(BIN, os.X_OK), f"Compiled daemon is not executable: {BIN}"
    with open(BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "archiver must be a compiled ELF executable, not a script or fake responder"

    proc = log = None
    roots = []
    try:
        proc, log = start_daemon(BIN)
        verify_fixed_end_to_end()
        tag = "bin_" + "".join(random.choice(string.ascii_lowercase) for _ in range(10))
        root, outside, expected = make_dynamic_tree(tag)
        roots.extend([root, outside])
        verify_dynamic(root, expected)
    finally:
        stop_daemon(proc, log)

    compiled = "/tmp/verifier_archiver_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-pthread", SRC, "-o", compiled, "-lhiredis"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"archiver.c did not compile successfully:\n{result.stdout}"
    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    proc = log = None
    try:
        proc, log = start_daemon(compiled)
        tag = "src_" + "".join(random.choice(string.ascii_lowercase) for _ in range(10))
        root, outside, expected = make_dynamic_tree(tag)
        roots.extend([root, outside])
        verify_dynamic(root, expected)
    finally:
        stop_daemon(proc, log)
        for path in roots:
            shutil.rmtree(path, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_archiver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
