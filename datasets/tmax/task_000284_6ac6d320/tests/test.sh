#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import struct
import subprocess
import tempfile


def test_01_extracted_files_content():
    expected_files = {
        "000000000001.bin": b"SOMEDATA_CONFIRMED_DATA12",
        "000000000002.bin": b"SOMEDATA_REJECTED_DATA",
        "000000000003.bin": b"CONFIRMED_START",
        "000000000004.bin": b"PENDING_WAITING",
        "000000000005.bin": b"ANOTHER_CONFIRMED_ITEM"
    }

    extracted_dir = "/home/user/extracted"
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist."

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(extracted_dir, filename)
        assert os.path.isfile(filepath), f"Expected extracted file {filepath} is missing."

        with open(filepath, "rb") as f:
            content = f.read()

        assert content == expected_content, f"Content of {filepath} is incorrect. Expected {expected_content}, got {content}."


def test_02_confirmed_txt_content():
    confirmed_path = "/home/user/confirmed.txt"
    assert os.path.isfile(confirmed_path), f"File {confirmed_path} is missing."

    with open(confirmed_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "000000000001",
        "000000000003",
        "000000000005"
    ]

    assert lines == expected_lines, f"Content of {confirmed_path} is incorrect. Expected {expected_lines}, got {lines}."


def test_03_cpp_source_exists():
    cpp_files = glob.glob("/home/user/*.cpp")
    assert len(cpp_files) > 0, "No C++ source file (.cpp) found in /home/user/."


def _build_rename_monitor(workdir):
    source = os.path.join(workdir, "rename_monitor.c")
    library = os.path.join(workdir, "rename_monitor.so")
    with open(source, "w") as f:
        f.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void record_success(const char *oldpath, const char *newpath, int result) {
    if (result != 0) return;
    const char *logpath = getenv("RENAME_LOG");
    if (!logpath) return;
    int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    dprintf(fd, "%s\t%s\n", oldpath ? oldpath : "", newpath ? newpath : "");
    close(fd);
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *) = NULL;
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    int result = real_rename(oldpath, newpath);
    record_success(oldpath, newpath, result);
    return result;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_renameat)(int, const char *, int, const char *) = NULL;
    if (!real_renameat) real_renameat = dlsym(RTLD_NEXT, "renameat");
    int result = real_renameat(olddirfd, oldpath, newdirfd, newpath);
    record_success(oldpath, newpath, result);
    return result;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd,
              const char *newpath, unsigned int flags) {
    static int (*real_renameat2)(int, const char *, int, const char *, unsigned int) = NULL;
    if (!real_renameat2) real_renameat2 = dlsym(RTLD_NEXT, "renameat2");
    if (!real_renameat2) return -1;
    int result = real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
    record_success(oldpath, newpath, result);
    return result;
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", source, "-o", library, "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    return library


def _write_random_repository(records):
    with open("/home/user/repository.bin", "wb") as f:
        for artifact_id, payload in records:
            f.write(b"ARTF")
            f.write(artifact_id.encode("ascii"))
            f.write(struct.pack("<I", len(payload)))
            f.write(bytes(value ^ 0x42 for value in payload))
            f.write(b"DONE")


def _reset_extracted():
    extracted = "/home/user/extracted"
    shutil.rmtree(extracted, ignore_errors=True)
    os.makedirs(extracted)


def _run_candidate(executable, records, monitor, workdir):
    _reset_extracted()
    _write_random_repository(records)
    rename_log = os.path.join(workdir, secrets.token_hex(8) + ".log")
    env = os.environ.copy()
    env["LD_PRELOAD"] = monitor
    env["RENAME_LOG"] = rename_log

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    if result.returncode != 0:
        return False, f"exited with status {result.returncode}: {result.stderr.decode(errors='replace')}"

    expected = {artifact_id + ".bin": payload for artifact_id, payload in records}
    actual_names = sorted(
        name for name in os.listdir("/home/user/extracted") if name.endswith(".bin")
    )
    if actual_names != sorted(expected):
        return False, f"produced .bin files {actual_names}, expected {sorted(expected)}"

    for name, payload in expected.items():
        path = os.path.join("/home/user/extracted", name)
        if not os.path.isfile(path):
            return False, f"missing dynamically requested output {path}"
        with open(path, "rb") as f:
            actual = f.read()
        if actual != payload:
            return False, f"incorrect dynamically requested payload in {path}"

    renames = []
    if os.path.exists(rename_log):
        with open(rename_log, "r", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) == 2:
                    renames.append(parts)

    for final_name in expected:
        matching = [
            (old, new) for old, new in renames
            if os.path.basename(new) == final_name and os.path.basename(old) != final_name
        ]
        if not matching:
            return False, f"no successful temporary-file rename created {final_name}"

    return True, ""


def test_04_cpp_extractor_handles_unknown_archive_and_uses_atomic_renames():
    cpp_files = sorted(glob.glob("/home/user/*.cpp"))
    assert cpp_files, "No C++ source file (.cpp) found in /home/user/."

    ids = set()
    while len(ids) < 7:
        ids.add(f"{secrets.randbits(48):012x}")

    records = []
    for index, artifact_id in enumerate(sorted(ids)):
        marker = b"CONFIRMED" if index % 3 == 0 else b"UNMATCHED"
        payload = secrets.token_bytes(7 + index) + marker + secrets.token_bytes(11 + index)
        records.append((artifact_id, payload))

    with tempfile.TemporaryDirectory(prefix="verify_extractor_") as workdir:
        monitor = _build_rename_monitor(workdir)
        source_sets = [cpp_files]
        if len(cpp_files) > 1:
            source_sets.extend([[path] for path in cpp_files])

        errors = []
        for index, sources in enumerate(source_sets):
            executable = os.path.join(workdir, f"candidate_{index}")
            compile_result = subprocess.run(
                ["g++", "-std=c++17", "-O2", *sources, "-o", executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            if compile_result.returncode != 0:
                errors.append(
                    f"Could not compile {sources}: "
                    + compile_result.stderr.decode(errors="replace")
                )
                continue

            try:
                passed, reason = _run_candidate(executable, records, monitor, workdir)
            except subprocess.TimeoutExpired:
                passed, reason = False, "execution timed out"
            if passed:
                return
            errors.append(f"Candidate built from {sources} failed: {reason}")

    assert False, "No submitted C++ source implemented the required extractor.\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
