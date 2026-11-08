#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import re
import shutil
import stat
import subprocess
import time
import uuid


def test_script_exists_and_executable():
    script_path = "/home/user/organize.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert not os.path.islink(script_path), f"Script {script_path} must not be a symlink."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_script_uses_flock():
    script_path = "/home/user/organize.sh"
    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, "The script does not seem to use 'flock'."
    assert "/tmp/project_organizer.lock" in content, "The script does not reference the correct lock file."


def test_organized_data_files():
    organized_dir = "/home/user/organized_data"
    assert os.path.isdir(organized_dir), f"Directory {organized_dir} does not exist."

    expected_files = {
        "GAMMA_v1.dat": "ID:GAMMA VER:1\nData for gamma 1\n",
        "GAMMA_v3.dat": "ID:GAMMA VER:3\nData for gamma 3\n",
        "OMEGA_v2.dat": "ID:OMEGA VER:2\nData for omega 2\n",
        "OMEGA_v10.dat": "ID:OMEGA VER:10\nData for omega 10\n"
    }

    actual_files = set(os.listdir(organized_dir))
    assert actual_files == set(expected_files.keys()), f"Expected files in {organized_dir} to be {list(expected_files.keys())}, but found {list(actual_files)}."

    for filename, expected_content in expected_files.items():
        file_path = os.path.join(organized_dir, filename)
        with open(file_path, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content of {filename} is incorrect."


def test_latest_data_symlinks():
    latest_dir = "/home/user/latest_data"
    assert os.path.isdir(latest_dir), f"Directory {latest_dir} does not exist."

    expected_links = {
        "GAMMA_latest.dat": "GAMMA_v3.dat",
        "OMEGA_latest.dat": "OMEGA_v10.dat"
    }

    actual_links = set(os.listdir(latest_dir))
    assert actual_links == set(expected_links.keys()), f"Expected symlinks in {latest_dir} to be {list(expected_links.keys())}, but found {list(actual_links)}."

    for link_name, target_name in expected_links.items():
        link_path = os.path.join(latest_dir, link_name)
        assert os.path.islink(link_path), f"{link_path} is not a symlink."

        target_path = os.readlink(link_path)
        if not os.path.isabs(target_path):
            target_path = os.path.normpath(os.path.join(latest_dir, target_path))

        expected_target_path = os.path.join("/home/user/organized_data", target_name)
        assert target_path == expected_target_path, f"Symlink {link_name} points to {target_path} instead of {expected_target_path}."


def test_manifest_checksums():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    organized_dir = "/home/user/organized_data"
    expected_checksums = {}
    for filename in ["GAMMA_v1.dat", "GAMMA_v3.dat", "OMEGA_v2.dat", "OMEGA_v10.dat"]:
        file_path = os.path.join(organized_dir, filename)
        with open(file_path, "rb") as f:
            expected_checksums[filename] = hashlib.sha256(f.read()).hexdigest()

    with open(manifest_path, "r") as f:
        manifest_lines = f.read().strip().splitlines()

    assert len(manifest_lines) == len(expected_checksums), "Manifest does not contain the correct number of entries."

    parsed_manifest = {}
    for line in manifest_lines:
        parts = line.split()
        assert len(parts) >= 2, f"Manifest line '{line}' is incorrectly formatted."
        checksum = parts[0]
        filename = os.path.basename(parts[1].lstrip('*'))
        parsed_manifest[filename] = checksum

    for filename, expected_checksum in expected_checksums.items():
        assert filename in parsed_manifest, f"{filename} is missing from the manifest."
        assert parsed_manifest[filename] == expected_checksum, f"Checksum for {filename} is incorrect in the manifest."


def test_project_inbox_cleanup():
    inbox_dir = "/home/user/project_inbox"
    assert os.path.isdir(inbox_dir), f"Directory {inbox_dir} does not exist."

    actual_files = set(os.listdir(inbox_dir))
    expected_files = {"readme.txt"}

    assert actual_files == expected_files, f"Expected {inbox_dir} to only contain {expected_files}, but found {actual_files}."


def test_script_on_fresh_inputs_with_locking_and_atomic_destination():
    script = "/home/user/organize.sh"
    inbox = "/home/user/project_inbox"
    organized = "/home/user/organized_data"
    latest = "/home/user/latest_data"
    tmpdir = "/home/user/tmp"

    for path in (inbox, organized, latest, tmpdir):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path)

    token = uuid.uuid4().hex[:10].upper()
    project_a = "DYN" + token
    project_b = "ALT" + token

    inputs = {
        "flattened_one.dat": f"ID:{project_a} VER:2\nDynamic version two\n".encode(),
        "unrelated_name.dat": f"ID:{project_a} VER:11\nDynamic version eleven\n".encode(),
        "bulk_payload.dat": f"ID:{project_b} VER:7\n".encode() + (b"Z" * (64 * 1024 * 1024)),
    }
    for name, data in inputs.items():
        with open(os.path.join(inbox, name), "wb") as f:
            f.write(data)

    invalid = {
        "malformed.dat": f"ID:{project_b} VER:8 trailing text\nMust not be processed\n".encode(),
        "missing_version.dat": f"ID:{project_b}\nMust not be processed\n".encode(),
        "metadata.txt": f"ID:{project_b} VER:99\nWrong extension\n".encode(),
    }
    for name, data in invalid.items():
        with open(os.path.join(inbox, name), "wb") as f:
            f.write(data)

    preexisting_name = f"{project_a}_v20.dat"
    preexisting_data = f"ID:{project_a} VER:20\nAlready organized\n".encode()
    with open(os.path.join(organized, preexisting_name), "wb") as f:
        f.write(preexisting_data)

    lock_fd = os.open("/tmp/project_organizer.lock", os.O_CREAT | os.O_RDWR, 0o666)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    proc = subprocess.Popen([script], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(0.5)

    assert all(os.path.exists(os.path.join(inbox, name)) for name in inputs), \
        "The script processed input while another process held the required lock."
    assert not os.path.exists(os.path.join(organized, f"{project_b}_v7.dat")), \
        "The script wrote output while another process held the required lock."

    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)

    if proc.poll() is not None:
        out, err = proc.communicate()
        assert proc.returncode == 0, f"Locked invocation failed unexpectedly: {out!r} {err!r}"
        proc = subprocess.Popen([script], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    large_target = os.path.join(organized, f"{project_b}_v7.dat")
    expected_large_size = len(inputs["bulk_payload.dat"])
    saw_partial_destination = False
    deadline = time.time() + 30
    while proc.poll() is None and time.time() < deadline:
        if os.path.exists(large_target):
            try:
                if os.path.getsize(large_target) != expected_large_size:
                    saw_partial_destination = True
            except FileNotFoundError:
                pass
        time.sleep(0.001)

    try:
        out, err = proc.communicate(timeout=max(1, int(deadline - time.time())))
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise AssertionError("Organizer did not finish within 30 seconds.")

    assert proc.returncode == 0, f"Organizer execution failed: {out!r} {err!r}"
    assert not saw_partial_destination, "A partially copied file became visible in organized_data; destination publication was not atomic."

    expected = {
        f"{project_a}_v2.dat": inputs["flattened_one.dat"],
        f"{project_a}_v11.dat": inputs["unrelated_name.dat"],
        f"{project_b}_v7.dat": inputs["bulk_payload.dat"],
        preexisting_name: preexisting_data,
    }
    assert set(os.listdir(organized)) == set(expected), "Fresh inputs were not parsed and organized correctly."
    for name, data in expected.items():
        path = os.path.join(organized, name)
        assert os.path.isfile(path) and not os.path.islink(path)
        with open(path, "rb") as f:
            assert hashlib.sha256(f.read()).digest() == hashlib.sha256(data).digest()

    assert set(os.listdir(inbox)) == set(invalid), "Successful .dat inputs were not removed, or invalid/non-.dat inputs were processed."
    for name, data in invalid.items():
        with open(os.path.join(inbox, name), "rb") as f:
            assert f.read() == data

    expected_links = {
        f"{project_a}_latest.dat": preexisting_name,
        f"{project_b}_latest.dat": f"{project_b}_v7.dat",
    }
    assert set(os.listdir(latest)) == set(expected_links)
    for link_name, target_name in expected_links.items():
        link = os.path.join(latest, link_name)
        assert os.path.islink(link)
        target = os.readlink(link)
        if not os.path.isabs(target):
            target = os.path.normpath(os.path.join(latest, target))
        assert target == os.path.join(organized, target_name)

    manifest_path = "/home/user/manifest.txt"
    with open(manifest_path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == len(expected)

    parsed = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\\s]+)", line)
        assert match, f"Manifest line is not standard sha256sum output with a base filename: {line!r}"
        assert match.group(2) not in parsed, "Manifest contains a duplicate filename."
        parsed[match.group(2)] = match.group(1)

    assert set(parsed) == set(expected)
    for name, data in expected.items():
        assert parsed[name] == hashlib.sha256(data).hexdigest()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
