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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import shutil
import signal
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8888"
UPLOAD_DIR = "/home/user/service_root/uploads"
SOURCE_DIR = "/app/archive-service-1.2.0"
INSTALL_DIR = "/home/user/service_root"


def create_tar_archive(files):
    tar_stream = io.BytesIO()
    with tarfile.open(fileobj=tar_stream, mode="w") as tar:
        for name, content in files.items():
            content_bytes = content.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(content_bytes)
            tar.addfile(info, io.BytesIO(content_bytes))
    return tar_stream.getvalue()


def create_link_archive(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w") as tar:
        for entry in entries:
            info = tarfile.TarInfo(entry[1])
            if entry[0] == "file":
                data = entry[2].encode()
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            elif entry[0] == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = entry[2]
                tar.addfile(info)
            elif entry[0] == "hardlink":
                info.type = tarfile.LNKTYPE
                info.linkname = entry[2]
                tar.addfile(info)
    return stream.getvalue()


def upload(data, timeout=10):
    return requests.post(f"{BASE_URL}/upload", data=data, timeout=timeout)


def wait_for(predicate, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def test_service_listening():
    try:
        requests.get(f"{BASE_URL}/", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:8888")

    # The required listener must be bound specifically to IPv4 loopback, not all interfaces.
    found = False
    with open("/proc/net/tcp") as f:
        for line in f.readlines()[1:]:
            local, state = line.split()[1], line.split()[3]
            address, port = local.split(":")
            if port.upper() == format(8888, "04X") and state == "0A":
                assert address == "0100007F", "service is not bound specifically to 127.0.0.1"
                found = True
    assert found, "no IPv4 listener found on port 8888"


def test_safe_upload():
    tar_data = create_tar_archive({"safe_file.txt": "safe content"})
    response = upload(tar_data)
    assert response.status_code in [200, 201, 204], f"Upload failed with status {response.status_code}"

    get_resp = requests.get(f"{BASE_URL}/files/safe_file.txt", timeout=3)
    assert get_resp.status_code == 200, "Failed to retrieve uploaded file via GET"
    assert get_resp.text == "safe content", "File content mismatch"


def test_zip_slip_vulnerability():
    malicious_path = "../../../../../../../../../../../home/user/flag.txt"
    tar_data = create_tar_archive({malicious_path: "pwned"})
    flag_path = "/home/user/flag.txt"
    if os.path.exists(flag_path):
        os.remove(flag_path)

    try:
        upload(tar_data)
    except Exception:
        pass

    assert not os.path.exists(flag_path), "Zip slip vulnerability exists! File was written outside UPLOAD_DIR."


def test_absolute_and_link_safety_and_safe_links():
    token = uuid.uuid4().hex
    absolute_target = f"/home/user/absolute-{token}.txt"
    outside_target = f"/home/user/link-target-{token}.txt"
    outside_existing = f"/home/user/hard-source-{token}.txt"
    for path in (absolute_target, outside_target, outside_existing):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Absolute member names must not escape the extraction root.
    try:
        upload(create_tar_archive({absolute_target: "absolute escape"}))
    except Exception:
        pass
    assert not os.path.exists(absolute_target), "absolute archive path escaped UPLOAD_DIR"

    safe_dir = f"links-{token}"
    safe_tar = create_link_archive([
        ("file", f"{safe_dir}/target.txt", "linked content"),
        ("symlink", f"{safe_dir}/symbolic.txt", "target.txt"),
        ("hardlink", f"{safe_dir}/hard.txt", f"{safe_dir}/target.txt"),
    ])
    response = upload(safe_tar)
    assert response.status_code in [200, 201, 204]
    target = os.path.join(UPLOAD_DIR, safe_dir, "target.txt")
    symbolic = os.path.join(UPLOAD_DIR, safe_dir, "symbolic.txt")
    hard = os.path.join(UPLOAD_DIR, safe_dir, "hard.txt")
    assert os.path.isfile(target)
    assert os.path.islink(symbolic), "safe symbolic link was not preserved"
    assert os.path.realpath(symbolic) == target
    assert os.path.isfile(hard), "safe hard link was not preserved"
    assert os.stat(target).st_ino == os.stat(hard).st_ino, "hard link was copied instead of preserved"

    # A symlink pivot followed by a regular member must neither leave an unsafe
    # link behind nor write the child outside the root.
    pivot = f"pivot-{token}"
    unsafe_symlink = create_link_archive([
        ("symlink", pivot, "/home/user"),
        ("file", f"{pivot}/link-target-{token}.txt", "escaped through symlink"),
    ])
    try:
        upload(unsafe_symlink)
    except Exception:
        pass
    assert not os.path.exists(outside_target), "archive wrote through an escaping symlink"
    assert not os.path.lexists(os.path.join(UPLOAD_DIR, pivot)), "escaping symlink was installed"

    with open(outside_existing, "w") as f:
        f.write("outside")
    evil_hard = f"evil-hard-{token}"
    try:
        upload(create_link_archive([("hardlink", evil_hard, outside_existing)]))
    except Exception:
        pass
    evil_hard_path = os.path.join(UPLOAD_DIR, evil_hard)
    assert not os.path.lexists(evil_hard_path), "hard link to a file outside UPLOAD_DIR was installed"
    assert open(outside_existing).read() == "outside"
    os.unlink(outside_existing)

    # Rejection of malicious archives must not kill the service.
    probe = create_tar_archive({f"post-malicious-{token}.txt": "alive"})
    assert upload(probe).status_code in [200, 201, 204]


def test_concurrency():
    num_threads = 5
    results = []

    def upload_task(i):
        tar_data = create_tar_archive({f"concurrent_{i}.txt": f"content_{i}"})
        try:
            resp = upload(tar_data)
            results.append((i, resp.status_code))
        except Exception as exc:
            results.append((i, str(exc)))

    threads = [threading.Thread(target=upload_task, args=(i,)) for i in range(num_threads)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    for i in range(num_threads):
        get_resp = requests.get(f"{BASE_URL}/files/concurrent_{i}.txt", timeout=3)
        assert get_resp.status_code == 200, f"Concurrent file {i} failed to upload or extract properly."
        assert get_resp.text == f"content_{i}", f"Concurrent file {i} content mismatch."


def test_streaming_threading_and_extraction_locking():
    token = uuid.uuid4().hex
    shared_name = f"stream-lock-{token}.txt"
    filler_name = f"large-{token}.bin"
    first = create_tar_archive({shared_name: "FIRST", filler_name: "x" * (2 * 1024 * 1024)})
    second = create_tar_archive({shared_name: "SECOND"})

    sock = socket.create_connection(("127.0.0.1", 8888), timeout=4)
    headers = (
        "POST /upload HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        f"Content-Length: {len(first)}\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    sock.sendall(headers)
    prefix = min(32768, len(first) - 1)
    sock.sendall(first[:prefix])

    shared_path = os.path.join(UPLOAD_DIR, shared_name)
    assert wait_for(lambda: os.path.exists(shared_path), 4), (
        "the first archive member was not extracted while the request was still arriving; "
        "the upload is being buffered instead of streamed"
    )
    assert open(shared_path).read() == "FIRST"

    # A single-threaded HTTPServer cannot answer this GET while the partial
    # upload is blocked waiting for more bytes.
    probe_name = f"thread-probe-{token}.txt"
    assert upload(create_tar_archive({probe_name: "probe"})).status_code in [200, 201, 204]
    get_result = {}

    def do_get():
        try:
            get_result["response"] = requests.get(f"{BASE_URL}/files/{probe_name}", timeout=1.5)
        except Exception as exc:
            get_result["error"] = exc

    get_thread = threading.Thread(target=do_get)
    get_thread.start()
    get_thread.join(2)
    assert not get_thread.is_alive() and "response" in get_result, "server serializes all HTTP request handling"
    assert get_result["response"].status_code == 200

    second_result = {}

    def upload_second():
        try:
            second_result["response"] = upload(second, timeout=10)
        except Exception as exc:
            second_result["error"] = exc

    second_thread = threading.Thread(target=upload_second)
    second_thread.start()
    time.sleep(0.7)
    assert second_thread.is_alive(), "a concurrent extraction entered the same target without waiting for the lock"
    assert open(shared_path).read() == "FIRST", "concurrent extraction modified files before the first extraction unlocked"

    sock.sendall(first[prefix:])
    sock.shutdown(socket.SHUT_WR)
    response_data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        response_data += chunk
    sock.close()
    assert b" 200 " in response_data or b" 201 " in response_data or b" 204 " in response_data

    second_thread.join(10)
    assert not second_thread.is_alive(), "locked extraction never completed"
    assert "response" in second_result, f"second upload failed: {second_result.get('error')}"
    assert second_result["response"].status_code in [200, 201, 204]
    assert open(shared_path).read() == "SECOND"


def test_install_directory():
    assert os.path.isdir(INSTALL_DIR), "Installation directory /home/user/service_root does not exist."
    assert os.path.isdir(UPLOAD_DIR), f"Upload directory {UPLOAD_DIR} does not exist."

    # Exercise the repaired Makefile, then verify the actual installed artifacts.
    subprocess.run(["make", "install"], cwd=SOURCE_DIR, check=True, timeout=15)
    for name in ("run.sh", "server.py", "config.ini"):
        source = os.path.join(SOURCE_DIR, name)
        installed = os.path.join(INSTALL_DIR, name)
        assert os.path.isfile(installed), f"make install did not install {name}"
        assert open(source, "rb").read() == open(installed, "rb").read(), f"installed {name} is stale"
    assert os.access(os.path.join(INSTALL_DIR, "run.sh"), os.X_OK), "installed run.sh is not executable"

    config = {}
    with open(os.path.join(INSTALL_DIR, "config.ini")) as f:
        for raw in f:
            raw = raw.strip()
            if raw and not raw.startswith(("#", ";")) and "=" in raw:
                key, value = raw.split("=", 1)
                config[key.strip()] = value.strip()
    assert config.get("PORT") == "8888"
    assert config.get("UPLOAD_DIR") == UPLOAD_DIR


def test_installed_run_script_parses_configuration():
    # Run an isolated copy with different values so a hard-coded port/path or
    # misspelled UPLOAD_DIR parser cannot pass merely because the main service works.
    sandbox = tempfile.mkdtemp(prefix="installed-service-")
    upload_dir = os.path.join(sandbox, "configured uploads")
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]

    for name in ("run.sh", "server.py"):
        shutil.copy2(os.path.join(INSTALL_DIR, name), os.path.join(sandbox, name))
    with open(os.path.join(sandbox, "config.ini"), "w") as f:
        f.write(f"# verifier configuration\nUPLOAD_DIR={upload_dir}\nPORT={port}\n")

    process = subprocess.Popen(
        [os.path.join(sandbox, "run.sh")],
        cwd=sandbox,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        url = f"http://127.0.0.1:{port}"
        assert wait_for(lambda: process.poll() is not None or _can_connect(port), 5), "installed run.sh did not start"
        assert process.poll() is None, "installed run.sh exited instead of starting the configured service"
        name = f"configured-{uuid.uuid4().hex}.txt"
        response = requests.post(f"{url}/upload", data=create_tar_archive({name: "configured"}), timeout=4)
        assert response.status_code in [200, 201, 204]
        assert os.path.isfile(os.path.join(upload_dir, name)), "run.sh ignored configured UPLOAD_DIR"
        assert open(os.path.join(upload_dir, name)).read() == "configured"
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
        shutil.rmtree(sandbox, ignore_errors=True)


def _can_connect(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
