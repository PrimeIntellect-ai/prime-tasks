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
import hashlib
import os
import pathlib
import shlex
import shutil
import tarfile
import time
import uuid

import pytest
import requests

PORT = 8192
BASE_URL = f"http://127.0.0.1:{PORT}"
SERVICE_DIR = pathlib.Path("/app/service").resolve()


def wait_for_service():
    for _ in range(10):
        try:
            response = requests.get(f"{BASE_URL}/api/status", timeout=1)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    return False


def listening_pids(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_address = fields[1]
            state = fields[3]
            if state != "0A":
                continue
            try:
                local_port = int(local_address.rsplit(":", 1)[1], 16)
            except ValueError:
                continue
            if local_port == port:
                socket_inodes.add(fields[9])

    pids = set()
    for proc_dir in pathlib.Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                pids.add(int(proc_dir.name))
                break
    return pids


def test_rust_release_service_is_listening():
    assert wait_for_service(), f"Service is not listening on port {PORT} or did not respond in time."

    cargo_toml = SERVICE_DIR / "Cargo.toml"
    assert cargo_toml.is_file(), "/app/service/Cargo.toml is missing."
    rust_sources = list(SERVICE_DIR.rglob("*.rs"))
    assert rust_sources, "No Rust source files were found under /app/service/."

    pids = listening_pids(PORT)
    assert pids, f"Could not identify a process listening on port {PORT}."
    for pid in pids:
        exe = pathlib.Path(os.path.realpath(f"/proc/{pid}/exe"))
        try:
            exe.relative_to(SERVICE_DIR / "target" / "release")
        except ValueError:
            pytest.fail(f"Listener PID {pid} is not the Cargo release binary: {exe}")
        assert exe.is_file(), f"Listener executable does not exist: {exe}"
        with exe.open("rb") as binary:
            assert binary.read(4) == b"\x7fELF", f"Listener executable is not an ELF binary: {exe}"


def test_api_status():
    assert wait_for_service(), f"Service is not listening on port {PORT} or did not respond in time."

    response = requests.get(f"{BASE_URL}/api/status", timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    expected_data = {"port": 8192, "quota": 150, "status": "running"}
    assert data == expected_data, f"Expected JSON {expected_data}, got {data}"


def normalized_archive_name(name):
    parts = [part for part in pathlib.PurePosixPath(name.lstrip("/")).parts if part not in ("", ".")]
    assert ".." not in parts, f"Unsafe archive member path: {name}"
    if parts[:2] == ["app", "storage"]:
        parts = parts[2:]
    elif parts[:1] == ["storage"]:
        parts = parts[1:]
    return "/".join(parts)


def test_api_backup():
    assert wait_for_service(), f"Service is not listening on port {PORT} or did not respond in time."

    archive_path = pathlib.Path("/app/backup/archive.tar.gz")
    if archive_path.exists():
        archive_path.unlink()

    storage = pathlib.Path("/app/storage")
    nonce_dir = storage / f"verifier-{uuid.uuid4().hex}"
    nonce_dir.mkdir()
    nonce_file = nonce_dir / "fresh-data.bin"
    nonce_file.write_bytes(os.urandom(65537))

    expected = {}
    for path in storage.rglob("*"):
        if path.is_file() and not path.is_symlink():
            expected[path.relative_to(storage).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()

    tar_executable = shutil.which("tar")
    assert tar_executable, "The required system tar command is unavailable."
    tar_path = pathlib.Path(os.path.realpath(tar_executable))
    real_tar = tar_path.with_name(f"{tar_path.name}.verifier-real-{os.getpid()}")
    marker = pathlib.Path(f"/tmp/tar-invoked-{uuid.uuid4().hex}")

    os.replace(tar_path, real_tar)
    tar_path.write_text(
        "#!/bin/sh\n"
        f"printf invoked > {shlex.quote(str(marker))}\n"
        f"exec {shlex.quote(str(real_tar))} \"$@\"\n"
    )
    tar_path.chmod(0o755)

    try:
        response = requests.post(f"{BASE_URL}/api/backup", timeout=15)
    finally:
        try:
            tar_path.unlink()
        finally:
            os.replace(real_tar, tar_path)

    try:
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert data == {"status": "success"}, f"Expected JSON {{'status': 'success'}}, got {data}"

        assert marker.exists(), "The backup endpoint did not execute the system tar command."
        assert archive_path.exists(), f"Backup archive {archive_path} was not created."
        assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

        actual = {}
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            base_names = [os.path.basename(name) for name in names]
            assert "file1.dat" in base_names, "file1.dat is missing from the backup archive."
            assert "file2.dat" in base_names, "file2.dat is missing from the backup archive."

            for member in tar.getmembers():
                if not member.isfile():
                    continue
                relative_name = normalized_archive_name(member.name)
                assert relative_name, f"Invalid regular-file member name: {member.name}"
                assert relative_name not in actual, f"Duplicate archive member for {relative_name}"
                extracted = tar.extractfile(member)
                assert extracted is not None
                actual[relative_name] = hashlib.sha256(extracted.read()).hexdigest()

        assert actual == expected, "Archive file names or contents do not exactly match /app/storage/."
    finally:
        marker.unlink(missing_ok=True)
        shutil.rmtree(nonce_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
