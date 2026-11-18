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
import os
import re
import signal
import struct
import subprocess
import tarfile
import tempfile
import time

import pytest
import requests

FRAMES_DIR = "/home/user/dataset/frames"
BASE_ARCHIVE = "/home/user/dataset/base_backup.tar"
DIFF_ARCHIVE = "/home/user/dataset/diff_backup.tar"
SNAPSHOT = "/home/user/dataset/snapshot.snar"
NAME_RE = re.compile(r"^evt(-?\d+)_val(-?\d+)_frm(\d+)\.jpg$")


def get_expected_filenames(start, end):
    filenames = []
    for i in range(start, end + 1):
        event_code = i % 5
        sensor_val = int(i * 3.14)
        filenames.append(f"evt{event_code}_val{sensor_val}_frm{i}.jpg")
    return filenames


def read_metadata(path="/app/metadata.bin"):
    data = open(path, "rb").read()
    assert len(data) == 16 + 100 * 16
    magic, version, count = struct.unpack_from("<4sIQ", data, 0)
    assert magic == b"DATA"
    assert version == 1
    assert count == 100
    return [struct.unpack_from("<IId", data, 16 + i * 16) for i in range(100)]


def metadata_names(records):
    return [f"evt{event}_val{int(sensor)}_frm{frame}.jpg"
            for frame, event, sensor in records]


def kill_port_8080_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    victims = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                victims.append(int(pid))
                break

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submitted_server():
    subprocess.run(
        ["gcc", "-O2", "-std=gnu11", "/home/user/server.c", "-o", "/tmp/verified_server"],
        check=True, timeout=20,
    )
    kill_port_8080_listener()
    proc = subprocess.Popen(
        ["/tmp/verified_server"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    last_error = None
    for _ in range(50):
        if proc.poll() is not None:
            pytest.fail(f"Compiled server exited immediately with status {proc.returncode}")
        try:
            r = requests.get("http://127.0.0.1:8080/backups/base", timeout=0.5)
            if r.status_code == 200:
                break
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    else:
        pytest.fail(f"Compiled server did not begin serving on 127.0.0.1:8080: {last_error}")
    # Deliberately leave the verified submitted server running after verification.
    yield proc


def test_c_files_exist():
    assert os.path.exists("/home/user/organize.c"), "/home/user/organize.c does not exist."
    assert os.path.exists("/home/user/server.c"), "/home/user/server.c does not exist."
    subprocess.run(
        ["gcc", "-O2", "-std=gnu11", "/home/user/organize.c", "-o", "/tmp/verified_organize"],
        check=True, timeout=20,
    )


def test_renamed_frames_exist():
    frames_dir = FRAMES_DIR
    assert os.path.isdir(frames_dir), f"Directory {frames_dir} does not exist."

    expected_files = get_expected_filenames(1, 100)
    actual_files = os.listdir(frames_dir)

    for expected in expected_files:
        assert expected in actual_files, f"Expected renamed file {expected} not found in {frames_dir}"

    # Also derive the names from the binary metadata rather than trusting formulas.
    derived = metadata_names(read_metadata())
    assert set(actual_files) == set(derived), "Frames directory does not contain exactly the metadata-derived names"


def decode_scaled(path, width=160, height=120):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1",
         "-vf", f"scale={width}:{height}:flags=area", "-pix_fmt", "rgb24",
         "-f", "rawvideo", "pipe:1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
    )
    assert result.returncode == 0, f"ffmpeg could not decode JPEG {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == width * height * 3, f"JPEG {path} did not decode to the expected 640x480 frame"
    return result.stdout


def test_frames_are_jpegs_from_the_corresponding_video_frames():
    records = read_metadata()
    names = metadata_names(records)
    width, height = 160, 120
    expected = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/experiment.mp4", "-frames:v", "100",
         "-vf", f"scale={width}:{height}:flags=area", "-pix_fmt", "rgb24",
         "-f", "rawvideo", "pipe:1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=30,
    ).stdout
    frame_size = width * height * 3
    assert len(expected) == 100 * frame_size, "Source video did not yield its first 100 frames"
    reference_frames = [expected[i * frame_size:(i + 1) * frame_size] for i in range(100)]

    seen_payloads = set()
    for index, name in enumerate(names):
        path = os.path.join(FRAMES_DIR, name)
        raw_file = open(path, "rb").read()
        assert raw_file.startswith(b"\xff\xd8") and raw_file.endswith(b"\xff\xd9"), f"{name} is not a JPEG file"
        decoded = decode_scaled(path, width, height)
        scores = [sum(abs(a - b) for a, b in zip(decoded, ref)) for ref in reference_frames]
        own_score = scores[index]
        assert own_score <= min(scores) + frame_size, f"{name} is not the corresponding frame from experiment.mp4"
        assert own_score / frame_size < 15, f"{name} differs excessively from the corresponding video frame"
        seen_payloads.add(decoded)
    assert len(seen_payloads) > 90, "The extracted frame set contains excessive duplicated imagery"


def verify_archive_payload(archive_bytes, expected_names):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(archive_bytes)
        tmp_path = tmp.name
    try:
        with tarfile.open(tmp_path, "r") as tar:
            members = tar.getmembers()
            regular = [m for m in members if m.isfile() and m.name.lower().endswith(".jpg")]
            by_basename = {}
            for member in regular:
                base = os.path.basename(member.name)
                assert base not in by_basename, f"Duplicate archived JPEG basename {base}"
                by_basename[base] = member
            assert set(by_basename) == set(expected_names), "Archive JPEG membership is not exactly the required frame set"
            for name in expected_names:
                archived = tar.extractfile(by_basename[name]).read()
                on_disk = open(os.path.join(FRAMES_DIR, name), "rb").read()
                assert archived == on_disk, f"Archived contents of {name} do not match the extracted frame"
            return members
    finally:
        os.remove(tmp_path)


def test_server_base_backup():
    try:
        response = requests.get("http://127.0.0.1:8080/backups/base", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server for base backup: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert "application/x-tar" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/x-tar"

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(response.content)
        tmp_path = tmp.name

    try:
        with tarfile.open(tmp_path, "r") as tar:
            members = tar.getnames()
            expected_files = get_expected_filenames(1, 50)
            for expected in expected_files:
                found = any(expected in member for member in members)
                assert found, f"Expected file {expected} not found in base_backup.tar"
    except tarfile.TarError:
        pytest.fail("Response body for base backup is not a valid tar archive.")
    finally:
        os.remove(tmp_path)

    assert os.path.isfile(BASE_ARCHIVE), "base_backup.tar does not exist on disk"
    assert response.content == open(BASE_ARCHIVE, "rb").read(), "Server did not serve base_backup.tar verbatim"
    verify_archive_payload(response.content, metadata_names(read_metadata())[:50])


def test_server_diff_backup():
    try:
        response = requests.get("http://127.0.0.1:8080/backups/diff", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server for diff backup: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert "application/x-tar" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/x-tar"

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(response.content)
        tmp_path = tmp.name

    try:
        with tarfile.open(tmp_path, "r") as tar:
            members = tar.getnames()
            expected_files = get_expected_filenames(51, 100)
            for expected in expected_files:
                found = any(expected in member for member in members)
                assert found, f"Expected file {expected} not found in diff_backup.tar"
    except tarfile.TarError:
        pytest.fail("Response body for diff backup is not a valid tar archive.")
    finally:
        os.remove(tmp_path)

    assert os.path.isfile(DIFF_ARCHIVE), "diff_backup.tar does not exist on disk"
    assert response.content == open(DIFF_ARCHIVE, "rb").read(), "Server did not serve diff_backup.tar verbatim"
    members = verify_archive_payload(response.content, metadata_names(read_metadata())[50:])
    assert os.path.isfile(SNAPSHOT) and os.path.getsize(SNAPSHOT) > 0, "snapshot.snar is missing or empty"
    assert open(SNAPSHOT, "rb").read(8) == b"GNU tar-", "snapshot.snar is not a GNU tar listed-incremental snapshot"
    assert any(m.type == tarfile.GNUTYPE_DUMPDIR for m in members), "diff_backup.tar is not a GNU tar incremental archive"


def test_organize_program_parses_metadata_and_performs_bulk_rename():
    records = read_metadata()
    original_names = metadata_names(records)
    original_metadata = open("/app/metadata.bin", "rb").read()
    modified_records = [(frame, event + 1000, sensor + 10000.25) for frame, event, sensor in records]
    modified_names = metadata_names(modified_records)

    for index, name in enumerate(original_names, 1):
        os.rename(os.path.join(FRAMES_DIR, name), os.path.join(FRAMES_DIR, f"frame_{index:03d}.jpg"))

    modified_metadata = bytearray(original_metadata[:16])
    for record in modified_records:
        modified_metadata.extend(struct.pack("<IId", *record))

    try:
        with open("/app/metadata.bin", "wb") as f:
            f.write(modified_metadata)
        subprocess.run(["/tmp/verified_organize"], cwd="/home/user", check=True, timeout=20)
        assert set(os.listdir(FRAMES_DIR)) == set(modified_names), "organize.c did not rename from modified metadata"

        for index, name in enumerate(modified_names, 1):
            os.rename(os.path.join(FRAMES_DIR, name), os.path.join(FRAMES_DIR, f"frame_{index:03d}.jpg"))
        with open("/app/metadata.bin", "wb") as f:
            f.write(original_metadata)
        subprocess.run(["/tmp/verified_organize"], cwd="/home/user", check=True, timeout=20)
        assert set(os.listdir(FRAMES_DIR)) == set(original_names), "organize.c did not restore the metadata-derived names"
    finally:
        with open("/app/metadata.bin", "wb") as f:
            f.write(original_metadata)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
