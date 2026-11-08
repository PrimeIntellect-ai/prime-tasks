#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time

CURATOR_DIR = "/home/user/curator"
CURATOR_BIN = os.path.join(CURATOR_DIR, "curator")
MAIN_GO = os.path.join(CURATOR_DIR, "main.go")
INCOMING = "/home/user/incoming"
REPO = "/home/user/repo"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(131072), b""):
            h.update(chunk)
    return h.hexdigest()


def create_archive(tar_path, app_name, version, payload_content):
    # Build the complete archive outside the watched directory, then atomically
    # move it in so the daemon never observes a partially-written gzip stream.
    fd, staged = tempfile.mkstemp(suffix=".tar.gz")
    os.close(fd)
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            manifest_path = os.path.join(tmpdir, "manifest.txt")
            with open(manifest_path, "w", encoding="utf-8") as f:
                f.write(f"AppName: {app_name}\nVersion: {version}\n")

            payload_path = os.path.join(tmpdir, "payload.bin")
            with open(payload_path, "wb") as f:
                f.write(payload_content)

            with tarfile.open(staged, "w:gz") as tar:
                tar.add(manifest_path, arcname="manifest.txt")
                tar.add(payload_path, arcname="payload.bin")
        expected_hash = sha256(staged)
        os.replace(staged, tar_path)
        return expected_hash
    finally:
        if os.path.exists(staged):
            os.unlink(staged)


def wait_for(predicate, message, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    assert predicate(), message


def clean_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.islink(item) or os.path.isfile(item):
            os.unlink(item)
        else:
            shutil.rmtree(item)


def stop_old_curator_processes():
    # Ask the agent-started instance to stop, then ensure it cannot interfere
    # with the controlled execution below.
    os.makedirs(INCOMING, exist_ok=True)
    shutdown = os.path.join(INCOMING, "SHUTDOWN.txt")
    try:
        with open(shutdown, "w", encoding="utf-8") as f:
            f.write("shutdown")
    except OSError:
        pass
    time.sleep(1)
    subprocess.run(["pkill", "-TERM", "-x", "curator"], check=False)
    time.sleep(0.5)
    subprocess.run(["pkill", "-KILL", "-x", "curator"], check=False)


def test_artifact_manager_behavior():
    # Preserve the original readiness and workspace assertions.
    status_file = os.path.join(CURATOR_DIR, "status.txt")
    assert os.path.exists(status_file), "status.txt was not created"
    with open(status_file, "r", encoding="utf-8") as f:
        status = f.read().strip()
    assert status == "READY", f"status.txt does not contain READY, got '{status}'"
    assert os.path.isdir(INCOMING), "incoming directory does not exist"
    assert os.path.isdir(REPO), "repo directory does not exist"

    # Verify that the requested source and executable really exist and are a
    # buildable Go/fsnotify program, rather than a collection of premade files.
    assert os.path.isfile(MAIN_GO), "main.go does not exist"
    with open(MAIN_GO, "r", encoding="utf-8") as f:
        source = f.read()
    assert "github.com/fsnotify/fsnotify" in source, "main.go does not use github.com/fsnotify/fsnotify"

    assert os.path.isfile(CURATOR_BIN), "curator executable does not exist"
    assert not os.path.islink(CURATOR_BIN), "curator must be an executable file, not a symlink"
    assert os.access(CURATOR_BIN, os.X_OK), "curator is not executable"
    with open(CURATOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "curator is not a Linux executable"

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/curator-source-build", "."],
        cwd=CURATOR_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Go project does not build:\n{build.stdout}"
    metadata = subprocess.run(
        ["go", "version", "-m", CURATOR_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert metadata.returncode == 0, f"cannot inspect curator Go binary: {metadata.stdout}"
    assert "github.com/fsnotify/fsnotify" in metadata.stdout, "curator binary was not built with fsnotify"

    stop_old_curator_processes()
    clean_directory(INCOMING)
    clean_directory(REPO)

    proc = subprocess.Popen(
        [CURATOR_BIN],
        cwd=CURATOR_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(0.5)
        assert proc.poll() is None, "curator exited before watching incoming"

        cases = []

        def submit(upload_name, app, version, payload):
            incoming_path = os.path.join(INCOMING, upload_name)
            expected_hash = create_archive(incoming_path, app, version, payload)
            destination = os.path.join(REPO, app, f"{app}-{version}.tar.gz")
            wait_for(
                lambda: os.path.isfile(destination) and not os.path.exists(incoming_path),
                f"archive {upload_name} was not moved to {destination}",
            )
            assert sha256(destination) == expected_hash, f"moved archive {destination} was not preserved byte-for-byte"
            cases.append((incoming_path, destination, expected_hash))

        # Keep the original fixed cases and assertions.
        submit("upload_abc123.tar.gz", "backend", "2.1.0", b"dummy payload")
        submit("upload_def456.tar.gz", "backend", "2.1.1", b"dummy payload 2")
        submit("upload_ghi789.tar.gz", "worker", "1.0.5", b"worker payload")

        # Add unpredictable names, manifest values, versions, and payloads so a
        # daemon cannot pass by precreating the verifier's known repository tree.
        token = secrets.token_hex(8)
        random_app = "app" + token
        random_v1 = f"{secrets.randbelow(80) + 10}.{secrets.randbelow(100)}.{secrets.randbelow(100)}-{secrets.token_hex(3)}"
        random_v2 = f"{secrets.randbelow(80) + 90}.{secrets.randbelow(100)}.{secrets.randbelow(100)}-{secrets.token_hex(3)}"
        submit(f"random-{secrets.token_hex(10)}.tar.gz", random_app, random_v1, secrets.token_bytes(4097))
        submit(f"random-{secrets.token_hex(10)}.tar.gz", random_app, random_v2, secrets.token_bytes(8193))

        backend_210 = os.path.join(REPO, "backend", "backend-2.1.0.tar.gz")
        backend_211 = os.path.join(REPO, "backend", "backend-2.1.1.tar.gz")
        worker_105 = os.path.join(REPO, "worker", "worker-1.0.5.tar.gz")
        assert os.path.isfile(backend_210), f"Missing {backend_210}"
        assert os.path.isfile(backend_211), f"Missing {backend_211}"
        assert os.path.isfile(worker_105), f"Missing {worker_105}"

        backend_latest = os.path.join(REPO, "backend", "latest.tar.gz")
        assert os.path.islink(backend_latest), f"{backend_latest} is not a symlink"
        backend_target = os.readlink(backend_latest)
        assert backend_target == "backend-2.1.1.tar.gz", f"backend symlink incorrect. Expected backend-2.1.1.tar.gz, got {backend_target}"

        worker_latest = os.path.join(REPO, "worker", "latest.tar.gz")
        assert os.path.islink(worker_latest), f"{worker_latest} is not a symlink"
        worker_target = os.readlink(worker_latest)
        assert worker_target == "worker-1.0.5.tar.gz", f"worker symlink incorrect. Expected worker-1.0.5.tar.gz, got {worker_target}"

        random_latest = os.path.join(REPO, random_app, "latest.tar.gz")
        assert os.path.islink(random_latest), f"{random_latest} is not a symlink"
        assert os.readlink(random_latest) == f"{random_app}-{random_v2}.tar.gz", "random app latest symlink was not updated relatively"
        assert not os.path.isabs(os.readlink(random_latest)), "latest symlink target must be relative"

        incoming_files = os.listdir(INCOMING)
        tarballs_left = [f for f in incoming_files if f.endswith(".tar.gz")]
        assert len(tarballs_left) == 0, f"Tarballs left in incoming directory: {tarballs_left}"

        # Exercise the required shutdown behavior on the exact submitted binary.
        shutdown_path = os.path.join(INCOMING, "SHUTDOWN.txt")
        with open(shutdown_path, "x", encoding="utf-8") as f:
            f.write("shutdown")
        try:
            return_code = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            raise AssertionError("curator did not terminate after SHUTDOWN.txt was created")
        assert return_code == 0, f"curator did not shut down gracefully; exit code was {return_code}"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
