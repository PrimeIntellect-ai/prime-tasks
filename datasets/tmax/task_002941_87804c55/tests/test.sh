#!/bin/bash
set -e
mkdir -p /logs/verifier

/start_services.sh
rm -rf /tmp/flask_uploads
mkdir -p /tmp/flask_uploads
redis-cli DEL backup:success >/dev/null

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import socket
import subprocess
import tarfile
import tempfile

import pytest

BINARY_PATH = "/home/user/safe_archiver/target/release/safe_archiver"
CLEAN_CORPUS = "/opt/corpora/clean"
EVIL_CORPUS = "/opt/corpora/evil"
UPLOAD_DIR = "/tmp/flask_uploads"


def get_redis_value(key):
    """Fetch a value from Redis using raw RESP protocol."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 6379))
        cmd = f"*2\r\n$3\r\nGET\r\n${len(key)}\r\n{key}\r\n"
        s.sendall(cmd.encode("utf-8"))
        data = s.recv(1024).decode("utf-8")
        s.close()
        if data.startswith("$"):
            parts = data.split("\r\n")
            if len(parts) >= 2:
                return parts[1]
        return None
    except Exception:
        return None


def upload_snapshot():
    result = {}
    if not os.path.isdir(UPLOAD_DIR):
        return result
    for name in sorted(os.listdir(UPLOAD_DIR)):
        path = os.path.join(UPLOAD_DIR, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                result[name] = hashlib.sha256(f.read()).hexdigest()
    return result


def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    name = name.rstrip("/")
    assert not name.startswith("/"), f"Archive contains absolute member {name!r}"
    parts = [p for p in name.split("/") if p not in ("", ".")]
    assert ".." not in parts, f"Archive contains traversal member {name!r}"
    return "/".join(parts)


def assert_archive_contents(path, input_basename, expected_files, expected_links):
    with tarfile.open(path, "r:gz") as tar:
        members = tar.getmembers()
        assert members, f"Archive {path} is empty"

        non_dirs = []
        for member in members:
            if member.isdir():
                continue
            non_dirs.append((normalized_member_name(member.name), member))

        expected_names = set(expected_files) | set(expected_links)
        candidates = []
        for prefix in ("", input_basename + "/"):
            converted = []
            valid = True
            for name, member in non_dirs:
                if prefix:
                    if not name.startswith(prefix):
                        valid = False
                        break
                    name = name[len(prefix):]
                converted.append((name, member))
            if valid and {name for name, _ in converted} == expected_names:
                candidates.append(converted)

        assert candidates, (
            f"Archive members do not match the input directory: "
            f"got {[name for name, _ in non_dirs]!r}, expected {sorted(expected_names)!r}"
        )
        converted = candidates[0]
        names = [name for name, _ in converted]
        assert len(names) == len(set(names)), "Archive contains duplicate file entries"

        by_name = dict(converted)
        for name, expected in expected_files.items():
            member = by_name[name]
            assert member.isfile(), f"{name} was not archived as a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file {name}"
            assert extracted.read() == expected, f"Archived contents differ for {name}"

        for name, target in expected_links.items():
            member = by_name[name]
            assert member.issym(), f"{name} was not preserved as a symbolic link"
            assert member.linkname == target, (
                f"Symlink {name} has target {member.linkname!r}, expected {target!r}"
            )


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Binary not found at {BINARY_PATH}. Did you build with --release?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."


def test_evil_corpus_rejected():
    evil_dirs = sorted([
        os.path.join(EVIL_CORPUS, d)
        for d in os.listdir(EVIL_CORPUS)
        if os.path.isdir(os.path.join(EVIL_CORPUS, d))
    ])
    assert len(evil_dirs) > 0, "No evil directories found to test."

    bypassed = []
    for i, directory in enumerate(evil_dirs):
        archive_name = f"evil_test_{i}.tar.gz"
        result = subprocess.run([BINARY_PATH, directory, archive_name], capture_output=True)
        if result.returncode != 1:
            bypassed.append(os.path.basename(directory))

    assert not bypassed, f"{len(bypassed)} of {len(evil_dirs)} evil bypassed: {bypassed}"


def test_clean_corpus_accepted():
    clean_dirs = sorted([
        os.path.join(CLEAN_CORPUS, d)
        for d in os.listdir(CLEAN_CORPUS)
        if os.path.isdir(os.path.join(CLEAN_CORPUS, d))
    ])
    assert len(clean_dirs) > 0, "No clean directories found to test."

    modified = []
    for i, directory in enumerate(clean_dirs):
        archive_name = f"clean_test_{i}.tar.gz"
        result = subprocess.run([BINARY_PATH, directory, archive_name], capture_output=True)
        if result.returncode != 0:
            modified.append(os.path.basename(directory))

    assert not modified, f"{len(modified)} of {len(clean_dirs)} clean modified/rejected: {modified}"


def test_redis_incremented():
    val = get_redis_value("backup:success")
    assert val is not None, "Could not retrieve backup:success from Redis."
    assert val == "10", f"Expected Redis backup:success to be 10, got {val}"


def test_flask_uploads():
    assert os.path.isdir(UPLOAD_DIR), f"Upload directory {UPLOAD_DIR} does not exist."
    uploads = [f for f in os.listdir(UPLOAD_DIR) if f.endswith(".tar.gz")]
    assert len(uploads) == 10, f"Expected 10 uploads in {UPLOAD_DIR}, found {len(uploads)}"

    for upload in uploads:
        path = os.path.join(UPLOAD_DIR, upload)
        try:
            with tarfile.open(path, "r:gz") as tar:
                members = tar.getmembers()
                assert len(members) > 0, f"Archive {upload} is empty."
        except Exception as exc:
            pytest.fail(f"Uploaded tarball {upload} is invalid or cannot be read: {exc}")

    for i in range(10):
        archive_name = f"clean_test_{i}.tar.gz"
        path = os.path.join(UPLOAD_DIR, archive_name)
        assert os.path.isfile(path), f"Expected upload {archive_name} was not received"
        assert_archive_contents(
            path,
            f"clean_{i + 1:02d}",
            {"file.txt": f"clean data {i + 1}\n".encode()},
            {"symlink.txt": "file.txt"},
        )


def test_randomized_malicious_directories_are_rejected_without_side_effects():
    root = tempfile.mkdtemp(prefix="archiver_case_")
    outside = os.path.join(root, secrets.token_hex(8))
    with open(outside, "wb") as f:
        f.write(secrets.token_bytes(97))

    cases = []

    absolute_case = os.path.join(root, secrets.token_hex(8))
    os.mkdir(absolute_case)
    os.symlink(outside, os.path.join(absolute_case, secrets.token_hex(4)))
    cases.append(absolute_case)

    relative_case = os.path.join(root, secrets.token_hex(8))
    os.mkdir(relative_case)
    os.symlink(os.path.relpath(outside, relative_case), os.path.join(relative_case, secrets.token_hex(4)))
    cases.append(relative_case)

    loop_case = os.path.join(root, secrets.token_hex(8))
    os.mkdir(loop_case)
    first = secrets.token_hex(4)
    second = secrets.token_hex(4)
    os.symlink(second, os.path.join(loop_case, first))
    os.symlink(first, os.path.join(loop_case, second))
    cases.append(loop_case)

    for directory in cases:
        archive_name = secrets.token_hex(12) + ".tar.gz"
        temporary_archive = os.path.join("/tmp", archive_name)
        if os.path.lexists(temporary_archive):
            os.unlink(temporary_archive)
        before_uploads = upload_snapshot()
        before_redis = get_redis_value("backup:success")

        result = subprocess.run([BINARY_PATH, directory, archive_name], capture_output=True)

        assert result.returncode == 1, f"Malicious randomized directory was not rejected: {directory}"
        assert result.stderr, "Rejection must print an error to standard error"
        assert upload_snapshot() == before_uploads, "Rejected input caused an upload"
        assert get_redis_value("backup:success") == before_redis, "Rejected input changed Redis"
        assert not os.path.lexists(temporary_archive), "Rejected input created an archive"


def test_randomized_clean_directories_are_archived_faithfully():
    initial_redis = int(get_redis_value("backup:success") or "0")
    initial_uploads = upload_snapshot()

    for case_number in range(3):
        root = tempfile.mkdtemp(prefix="archiver_case_")
        directory = os.path.join(root, secrets.token_hex(8))
        nested = os.path.join(directory, "nested")
        os.makedirs(nested)

        payload = secrets.token_bytes(257 + case_number)
        top = ("token-" + secrets.token_hex(24) + "\n").encode()
        child = secrets.token_bytes(43)
        with open(os.path.join(directory, "payload.bin"), "wb") as f:
            f.write(payload)
        with open(os.path.join(directory, "top.txt"), "wb") as f:
            f.write(top)
        with open(os.path.join(nested, "child.dat"), "wb") as f:
            f.write(child)
        with open(os.path.join(nested, "empty"), "wb"):
            pass

        os.symlink("payload.bin", os.path.join(directory, "payload-link"))
        os.symlink("../top.txt", os.path.join(nested, "top-link"))
        os.symlink("nested", os.path.join(directory, "directory-link"))

        archive_name = secrets.token_hex(12) + ".tar.gz"
        result = subprocess.run([BINARY_PATH, directory, archive_name], capture_output=True)
        assert result.returncode == 0, (
            f"Valid randomized directory was rejected: stderr={result.stderr.decode(errors='replace')}"
        )

        uploaded = os.path.join(UPLOAD_DIR, archive_name)
        assert os.path.isfile(uploaded), f"Expected randomized upload {archive_name} was not received"
        assert_archive_contents(
            uploaded,
            os.path.basename(directory),
            {
                "payload.bin": payload,
                "top.txt": top,
                "nested/child.dat": child,
                "nested/empty": b"",
            },
            {
                "payload-link": "payload.bin",
                "nested/top-link": "../top.txt",
                "directory-link": "nested",
            },
        )

        assert int(get_redis_value("backup:success") or "0") == initial_redis + case_number + 1

    final_uploads = upload_snapshot()
    assert len(final_uploads) == len(initial_uploads) + 3
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
