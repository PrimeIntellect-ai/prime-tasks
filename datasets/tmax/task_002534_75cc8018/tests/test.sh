#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest


def get_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def test_output_directory_exists():
    out_dir = "/home/user/output"
    assert os.path.isdir(out_dir), f"Output directory {out_dir} does not exist."


def test_extracted_files_content():
    expected_files = {
        "intro.md": "b04be124e4d5fb737d9be70dc5d72f91",
        "setup.md": "bdd6631b518c7ed6184da3109a25d252",
        "api.md": "fd787327fc0ffdd0cf3b10b067a57ebc"
    }

    for filename, expected_md5 in expected_files.items():
        file_path = os.path.join("/home/user/output", filename)
        assert os.path.isfile(file_path), f"Extracted file {file_path} does not exist."
        actual_md5 = get_md5(file_path)
        assert actual_md5 == expected_md5, f"Content of {filename} is incorrect. Expected MD5 {expected_md5}, got {actual_md5}."


def test_extractor_c_flock():
    c_path = "/home/user/extractor.c"
    assert os.path.isfile(c_path), f"Source file {c_path} is missing."
    with open(c_path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert re.search(r"flock\s*\([^,]+,\s*LOCK_EX\s*\)", content) or \
           re.search(r"flock\s*\([^,]+,\s*[^,]*LOCK_EX[^,]*\)", content) or \
           ("flock" in content and "LOCK_EX" in content), \
           "The C program does not appear to use flock() with LOCK_EX."

    # Comments and string literals do not count as an implementation.
    token_re = re.compile(
        r'("(?:\\.|[^"\\])*")|(\'(?:\\.|[^\'\\])*\')|(/\*.*?\*/|//[^\n]*)',
        re.DOTALL,
    )

    def strip_non_code(match):
        if match.group(1) is not None or match.group(2) is not None:
            return '\"\"'
        return "\n" * match.group(0).count("\n")

    code = token_re.sub(strip_non_code, content)
    assert re.search(
        r"\bflock\s*\(\s*[^,;{}]+\s*,\s*[^);{}]*\bLOCK_EX\b[^);{}]*\)",
        code,
    ), "extractor.c must contain a real flock(..., LOCK_EX) call, not only keywords in comments or strings."


def test_extractor_compiled():
    bin_path = "/home/user/extractor"
    assert os.path.isfile(bin_path), f"Compiled executable {bin_path} does not exist."
    st = os.stat(bin_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"File {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled ELF executable."


def test_source_and_binary_extract_dynamic_inputs_with_file_locks():
    conf_path = Path("/home/user/split.conf")
    blob_path = Path("/home/user/docs_blob.bin")
    output_path = Path("/home/user/output")
    source_path = Path("/home/user/extractor.c")
    binary_path = Path("/home/user/extractor")

    work = Path(tempfile.mkdtemp(prefix="extractor_verify_"))
    original_conf = conf_path.read_bytes()
    original_blob = blob_path.read_bytes()
    had_output = output_path.is_dir()
    backup_output = work / "original_output"
    if had_output:
        shutil.copytree(output_path, backup_output)

    try:
        rebuilt = work / "extractor_from_source"
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O0", "-Wall", "-Wextra", str(source_path), "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"extractor.c does not compile with gcc:\n{compile_result.stderr}"

        interposer_source = work / "flock_probe.c"
        interposer = work / "flock_probe.so"
        interposer_source.write_text(r'''
#define _GNU_SOURCE
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>

int flock(int fd, int operation) {
    struct stat st;
    char linkname[64];
    char target[4096];
    ssize_t n;
    long long size = -1;
    int rc = (int)syscall(SYS_flock, fd, operation);

    if (fstat(fd, &st) == 0)
        size = (long long)st.st_size;
    snprintf(linkname, sizeof(linkname), "/proc/self/fd/%d", fd);
    n = readlink(linkname, target, sizeof(target) - 1);
    if (n < 0) {
        target[0] = '\0';
    } else {
        target[n] = '\0';
    }

    const char *log_path = getenv("FLOCK_LOG");
    if (log_path) {
        int logfd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (logfd >= 0) {
            dprintf(logfd, "%d|%d|%lld|%s\n", rc, operation, size, target);
            close(logfd);
        }
    }
    return rc;
}
''')
        probe_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", str(interposer_source), "-o", str(interposer)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert probe_result.returncode == 0, f"Could not build flock probe:\n{probe_result.stderr}"

        expected = {
            "alpha.md": b"# Alpha\nDynamically generated first document.\n",
            "beta.md": b"# Beta\nA second test chunk at another offset.\n",
            "gamma.md": b"# Gamma\nFinal verifier-generated markdown.\n",
        }
        offsets = {"alpha.md": 17, "beta.md": 103, "gamma.md": 181}
        decoded_blob = bytearray(b"." * 280)
        for name, data in expected.items():
            start = offsets[name]
            decoded_blob[start:start + len(data)] = data
        blob_path.write_bytes(bytes(value ^ 0x42 for value in decoded_blob))
        conf_path.write_text(
            "beta.md:{0}:{1}\nalpha.md:{2}:{3}\ngamma.md:{4}:{5}\n".format(
                offsets["beta.md"], len(expected["beta.md"]),
                offsets["alpha.md"], len(expected["alpha.md"]),
                offsets["gamma.md"], len(expected["gamma.md"]),
            )
        )

        for label, candidate in (("submitted executable", binary_path), ("extractor.c rebuilt with gcc", rebuilt)):
            if output_path.exists():
                shutil.rmtree(output_path)
            log_path = work / ("flock_" + label.replace(" ", "_") + ".log")
            env = os.environ.copy()
            env["LD_PRELOAD"] = str(interposer)
            env["FLOCK_LOG"] = str(log_path)
            result = subprocess.run(
                [str(candidate)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                timeout=20,
            )
            assert result.returncode == 0, f"The {label} failed on verifier-generated input:\n{result.stderr}"
            assert output_path.is_dir(), f"The {label} did not create /home/user/output."

            for name, data in expected.items():
                produced = output_path / name
                assert produced.is_file(), f"The {label} did not create {produced}."
                assert produced.read_bytes() == data, f"The {label} decoded {name} incorrectly."

            assert log_path.is_file(), f"The {label} made no observable flock() calls."
            lock_records = []
            for line in log_path.read_text().splitlines():
                parts = line.split("|", 3)
                if len(parts) == 4:
                    lock_records.append((int(parts[0]), int(parts[1]), int(parts[2]), os.path.realpath(parts[3])))

            for name in expected:
                wanted = os.path.realpath(str(output_path / name))
                assert any(
                    rc == 0 and (operation & 2) == 2 and size == 0 and path == wanted
                    for rc, operation, size, path in lock_records
                ), f"The {label} did not acquire LOCK_EX on {name} before writing it."
    finally:
        conf_path.write_bytes(original_conf)
        blob_path.write_bytes(original_blob)
        if output_path.exists():
            shutil.rmtree(output_path)
        if had_output:
            shutil.copytree(backup_output, output_path)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
