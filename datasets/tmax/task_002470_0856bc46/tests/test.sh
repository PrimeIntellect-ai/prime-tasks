#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import tarfile

import pytest


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_archiver_c_exists_and_uses_rename():
    c_file = "/home/user/archiver.c"
    assert os.path.isfile(c_file), f"{c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert "rename(" in content, "The C program must use the rename() function for atomic writes."


def test_archiver_exists_and_is_executable_elf():
    archiver = "/home/user/archiver"
    assert os.path.isfile(archiver), f"{archiver} is missing."
    assert os.access(archiver, os.X_OK), f"{archiver} is not executable."
    with open(archiver, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{archiver} is not a compiled ELF executable."


def test_manifest_content():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"{manifest_path} is missing."

    expected_files = ["network.conf", "cache.conf"]
    expected_lines = set()
    for filename in expected_files:
        filepath = os.path.join("/home/user/configs", filename)
        assert os.path.isfile(filepath), f"Expected config file {filepath} is missing."
        file_hash = get_sha256(filepath)
        expected_lines.add(f"{file_hash}  {filename}")

    with open(manifest_path, "r") as f:
        manifest_lines = set(line.strip() for line in f if line.strip())

    assert manifest_lines == expected_lines, (
        f"Manifest contents do not match expected.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {manifest_lines}"
    )


def test_tarball_content():
    tarball_path = "/home/user/incremental.tar.gz"
    assert os.path.isfile(tarball_path), f"{tarball_path} is missing."

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getnames()
    except tarfile.ReadError:
        pytest.fail(f"{tarball_path} is not a valid gzip-compressed tarball.")

    expected_members = {"network.conf", "cache.conf"}
    actual_members = set(members)

    assert actual_members == expected_members, (
        f"Tarball contents do not match expected.\n"
        f"Expected: {expected_members}\n"
        f"Got: {actual_members}\n"
        f"Make sure to not include the configs/ directory structure."
    )


def build_rename_auditor():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *) = NULL;
    if (!real_rename)
        real_rename = dlsym(RTLD_NEXT, "rename");

    const char *logpath = getenv("RENAME_AUDIT_LOG");
    struct stat st;
    int source_exists = (lstat(oldpath, &st) == 0 && S_ISREG(st.st_mode));
    if (logpath) {
        int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            dprintf(fd, "%ld\t%s\t%s\t%d\n", (long)getpid(), oldpath,
                    newpath, source_exists);
            close(fd);
        }
    }
    return real_rename(oldpath, newpath);
}
'''
    c_path = "/tmp/rename_audit.c"
    so_path = "/tmp/rename_audit.so"
    with open(c_path, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", so_path, c_path, "-ldl"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Could not build rename auditor: {result.stderr}"
    return so_path


def test_archiver_parses_latest_block_and_runs_atomically():
    token = secrets.token_hex(8)
    selected = [f"service-{token}.conf", f"feature-{token}.conf"]
    decoy = f"old-{token}.conf"
    contents = {
        selected[0]: f"service_token={token}\nmode=active\n".encode(),
        selected[1]: f"feature_token={token}\nenabled=true\n".encode(),
        decoy: f"obsolete={token}\n".encode(),
    }

    config_dir = "/home/user/configs"
    for name, data in contents.items():
        with open(os.path.join(config_dir, name), "wb") as f:
            f.write(data)

    with open("/home/user/config_log.txt", "w") as f:
        f.write(
            "[UPDATE]\n"
            "Date: 2026-01-01\n"
            "Author: decoy\n"
            "Modified:\n"
            f" - {decoy}\n"
            "[END]\n\n"
            "[UPDATE]\n"
            "Date: 2026-01-02\n"
            "Author: verifier\n"
            "Modified:\n"
            f" - {selected[0]}\n"
            f" - {selected[1]}\n"
            "[END]\n"
        )

    for path in [
        "/home/user/manifest.txt",
        "/home/user/manifest.txt.tmp",
        "/home/user/incremental.tar.gz",
        "/tmp/rename_audit.log",
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    auditor = build_rename_auditor()
    env = os.environ.copy()
    env["LD_PRELOAD"] = auditor
    env["RENAME_AUDIT_LOG"] = "/tmp/rename_audit.log"
    proc = subprocess.Popen(
        ["/home/user/archiver"],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        pytest.fail("/home/user/archiver timed out")

    assert proc.returncode == 0, (
        f"archiver exited with {proc.returncode}\nstdout: {stdout}\nstderr: {stderr}"
    )

    assert os.path.isfile("/tmp/rename_audit.log"), (
        "No call to the C rename() function was observed while archiver ran."
    )
    with open("/tmp/rename_audit.log") as f:
        events = [line.rstrip("\n").split("\t") for line in f]
    assert any(
        len(event) == 4
        and event[0] == str(proc.pid)
        and event[1] == "/home/user/manifest.txt.tmp"
        and event[2] == "/home/user/manifest.txt"
        and event[3] == "1"
        for event in events
    ), "archiver must rename an existing manifest.txt.tmp to manifest.txt using C rename()."
    assert not os.path.exists("/home/user/manifest.txt.tmp"), (
        "The temporary manifest still exists after successful completion."
    )

    expected_lines = {
        f"{hashlib.sha256(contents[name]).hexdigest()}  {name}" for name in selected
    }
    with open("/home/user/manifest.txt", "r") as f:
        actual_lines = [line.rstrip("\n") for line in f]
    assert len(actual_lines) == len(expected_lines)
    assert set(actual_lines) == expected_lines, (
        f"Manifest was not derived from the last update block: {actual_lines}"
    )

    try:
        with tarfile.open("/home/user/incremental.tar.gz", "r:gz") as tar:
            members = tar.getmembers()
            assert {member.name for member in members} == set(selected)
            assert all(member.isfile() for member in members)
            for member in members:
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == contents[member.name], (
                    f"Archived content for {member.name} does not match the config file."
                )
    except (tarfile.ReadError, FileNotFoundError) as exc:
        pytest.fail(f"incremental.tar.gz is missing or invalid: {exc}")


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
