#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import stat
import subprocess
import tarfile

import pytest


def test_safe_configs_hard_links():
    incoming_dir = "/home/user/incoming_configs"
    safe_dir = "/home/user/safe_configs"

    expected_safe = ["app1_update.tar", "app2_update.tar"]

    for filename in expected_safe:
        incoming_path = os.path.join(incoming_dir, filename)
        safe_path = os.path.join(safe_dir, filename)

        assert os.path.exists(safe_path), f"Safe config missing: {safe_path}"
        assert not os.path.islink(safe_path), f"Expected hard link, but found symlink for {safe_path}"

        incoming_stat = os.stat(incoming_path)
        safe_stat = os.stat(safe_path)

        assert incoming_stat.st_ino == safe_stat.st_ino, f"Inode mismatch for {filename}: not a hard link"


def test_quarantine_configs_symlinks():
    incoming_dir = "/home/user/incoming_configs"
    quarantine_dir = "/home/user/quarantine_configs"

    expected_malicious = ["evil_relative.tar", "evil_absolute.tar"]

    for filename in expected_malicious:
        incoming_path = os.path.join(incoming_dir, filename)
        quarantine_path = os.path.join(quarantine_dir, filename)

        assert os.path.exists(quarantine_path) or os.path.islink(quarantine_path), f"Quarantine config missing: {quarantine_path}"
        assert os.path.islink(quarantine_path), f"Expected symlink for {quarantine_path}"

        target = os.readlink(quarantine_path)
        assert os.path.abspath(os.path.join(quarantine_dir, target)) == os.path.abspath(incoming_path), f"Symlink target mismatch for {filename}"


def test_corrupted_log():
    log_path = "/home/user/corrupted.log"
    assert os.path.isfile(log_path), f"Corrupted log file missing: {log_path}"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_corrupted = {"broken1.tar", "broken2.tar"}
    assert set(lines) == expected_corrupted, f"Corrupted log contents mismatch. Expected {expected_corrupted}, got {set(lines)}"
    assert len(lines) == 2, f"Corrupted log should contain exactly 2 lines, got {len(lines)}"


def test_compiled_binary_exists():
    binary_path = "/home/user/config_filter"
    assert os.path.isfile(binary_path), f"Compiled binary missing: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Compiled binary is not executable: {binary_path}"


def test_no_extra_files_in_directories():
    safe_dir = "/home/user/safe_configs"
    quarantine_dir = "/home/user/quarantine_configs"

    safe_files = set(os.listdir(safe_dir))
    quarantine_files = set(os.listdir(quarantine_dir))

    expected_safe = {"app1_update.tar", "app2_update.tar"}
    expected_quarantine = {"evil_relative.tar", "evil_absolute.tar"}

    assert safe_files == expected_safe, f"Unexpected files in safe_configs: {safe_files}"
    assert quarantine_files == expected_quarantine, f"Unexpected files in quarantine_configs: {quarantine_files}"


def _write_tar(path, member_names):
    with tarfile.open(path, "w") as archive:
        for index, member_name in enumerate(member_names):
            payload = (f"generated configuration {index}\n").encode()
            info = tarfile.TarInfo(member_name)
            info.size = len(payload)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(payload))


def _prepare_case():
    incoming = "/home/user/incoming_configs"
    safe = "/home/user/safe_configs"
    quarantine = "/home/user/quarantine_configs"

    for directory in (incoming, safe, quarantine):
        shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(directory, mode=0o777)
        os.chmod(directory, 0o777)

    token = secrets.token_hex(8)
    safe_names = {f"normal_{token}.tar", f"nested_{token}.tar"}
    relative_name = f"relative_{token}.tar"
    absolute_name = f"absolute_{token}.tar"
    corrupt_name = f"corrupt_{token}.tar"

    _write_tar(os.path.join(incoming, f"normal_{token}.tar"), [f"config_{token}.json"])
    _write_tar(os.path.join(incoming, f"nested_{token}.tar"), [f"app_{token}/settings/value.conf"])
    _write_tar(os.path.join(incoming, relative_name), [f"folder/../escaped_{token}.conf"])
    _write_tar(os.path.join(incoming, absolute_name), [f"/tmp/escaped_{token}.conf"])

    with open(os.path.join(incoming, corrupt_name), "wb") as stream:
        stream.write(b"not a tar archive\n" + os.urandom(713))

    with open(os.path.join(incoming, f"ignored_{token}.txt"), "w") as stream:
        stream.write("not an archive")

    return safe_names, {relative_name, absolute_name}, {corrupt_name}


def _assert_program_behavior(executable):
    expected_safe, expected_malicious, expected_corrupt = _prepare_case()
    log_path = "/home/user/corrupted.log"

    with open(log_path, "wb") as error_log:
        result = subprocess.run(
            [executable],
            stdout=subprocess.DEVNULL,
            stderr=error_log,
            timeout=20,
            check=False,
        )
    assert result.returncode == 0, f"{executable} exited with status {result.returncode}"

    incoming = "/home/user/incoming_configs"
    safe = "/home/user/safe_configs"
    quarantine = "/home/user/quarantine_configs"

    assert set(os.listdir(safe)) == expected_safe
    assert set(os.listdir(quarantine)) == expected_malicious

    for filename in expected_safe:
        source = os.path.join(incoming, filename)
        link = os.path.join(safe, filename)
        assert os.path.isfile(link)
        assert not os.path.islink(link)
        assert os.stat(source).st_ino == os.stat(link).st_ino

    for filename in expected_malicious:
        source = os.path.join(incoming, filename)
        link = os.path.join(quarantine, filename)
        assert os.path.islink(link)
        assert os.path.realpath(link) == os.path.realpath(source)

    for filename in expected_corrupt:
        assert not os.path.lexists(os.path.join(safe, filename))
        assert not os.path.lexists(os.path.join(quarantine, filename))

    with open(log_path, "r", errors="replace") as stream:
        lines = [line.strip() for line in stream if line.strip()]
    assert lines == list(expected_corrupt), f"stderr log must contain only corrupted basenames, got {lines}"


def test_program_and_cpp_implementation_on_generated_archives(tmp_path):
    source = "/home/user/config_filter.cpp"
    binary = "/home/user/config_filter"

    assert os.path.isfile(source), f"C++ source missing: {source}"
    assert stat.S_ISREG(os.lstat(source).st_mode), "C++ source must be a regular file"
    assert stat.S_ISREG(os.lstat(binary).st_mode), "Compiled binary must be a regular file"
    with open(binary, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "config_filter is not a compiled ELF binary"

    _assert_program_behavior(binary)

    rebuilt = str(tmp_path / "config_filter_rebuilt")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert compile_result.returncode == 0, f"config_filter.cpp failed to compile:\n{compile_result.stderr}"
    _assert_program_behavior(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
