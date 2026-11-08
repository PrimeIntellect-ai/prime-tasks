#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'C_EOF' > /tmp/mmap_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

static void record_target_mapping(int fd) {
    if (fd < 0) return;
    const char *target = getenv("MMAP_AUDIT_TARGET");
    const char *log = getenv("MMAP_AUDIT_LOG");
    if (!target || !log) return;

    char linkname[64];
    char path[PATH_MAX + 1];
    snprintf(linkname, sizeof(linkname), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(linkname, path, PATH_MAX);
    if (n < 0) return;
    path[n] = '\0';

    if (strcmp(path, target) == 0) {
        int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            char line[64];
            int len = snprintf(line, sizeof(line), "%ld\n", (long)getpid());
            if (len > 0) write(out, line, (size_t)len);
            close(out);
        }
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    record_target_mapping(fd);
    return result;
}

#ifdef __USE_LARGEFILE64
void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
    static void *(*real_mmap64)(void *, size_t, int, int, int, off64_t) = NULL;
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    void *result = real_mmap64(addr, length, prot, flags, fd, offset);
    record_target_mapping(fd);
    return result;
}
#endif
C_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import uuid

import pytest

CLASSIFIER_PATH = "/home/user/classifier"
CLASSIFIER_SOURCE = "/home/user/classifier.rs"
EVIL_CORPUS = "/app/verifier_corpus/evil"
CLEAN_CORPUS = "/app/verifier_corpus/clean"
INCOMING_CORPUS = "/app/corpus/incoming"
VERIFIED_DIR = "/home/user/repo_verified"
QUARANTINE_DIR = "/home/user/repo_quarantine"
VIDEO_PATH = "/app/incident_record.mp4"
SIGNATURE = b"\xDE\xAD\xBE\xEF\x42\x13\x37"


def extract_video_signature():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO_PATH, "-map", "0:s:0", "-f", "srt", "-"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Could not extract subtitle track: {result.stderr}"
    match = re.search(r"PAYLOAD_SIG:\s*((?:0x[0-9A-Fa-f]{2}\s*)+)", result.stdout)
    assert match, "PAYLOAD_SIG was not found in the video's subtitle track"
    return bytes(int(value, 16) for value in re.findall(r"0x([0-9A-Fa-f]{2})", match.group(1)))


@pytest.fixture(scope="session")
def video_signature():
    signature = extract_video_signature()
    assert signature == SIGNATURE, "The incident video's extracted signature is unexpected"
    return signature


@pytest.fixture(scope="session")
def mmap_audit_library():
    output = "/tmp/mmap_audit.so"
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", output, "/tmp/mmap_audit.c", "-ldl"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Failed to build mmap audit library: {result.stderr}"
    return output


@pytest.fixture(scope="session")
def rebuilt_classifier(tmp_path_factory):
    assert os.path.isfile(CLASSIFIER_SOURCE), f"Rust source not found at {CLASSIFIER_SOURCE}"
    source = open(CLASSIFIER_SOURCE, "r", encoding="utf-8").read()
    assert re.search(r"\bmemmap2\s*::", source), "classifier.rs does not import memmap2"
    assert re.search(r"\b(?:Mmap|MmapOptions)\b", source), "classifier.rs does not use a memmap2 mapping type"
    assert re.search(r"(?:::|\.)map(?:_copy|_exec)?\s*\(", source), "classifier.rs does not create a memory map"

    project = tmp_path_factory.mktemp("classifier_rebuild")
    src_dir = project / "src"
    src_dir.mkdir()
    shutil.copyfile(CLASSIFIER_SOURCE, src_dir / "main.rs")
    (project / "Cargo.toml").write_text(
        '[package]\nname = "submitted_classifier_check"\nversion = "0.1.0"\nedition = "2021"\n\n'
        '[dependencies]\nmemmap2 = "0.9"\n',
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["CARGO_HOME"] = "/usr/local/cargo"
    env["RUSTUP_HOME"] = "/usr/local/rustup"
    result = subprocess.run(
        ["cargo", "build", "--release", "--offline"],
        cwd=project,
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"classifier.rs does not build with memmap2:\n{result.stderr}"
    return str(project / "target" / "release" / "submitted_classifier_check")


def test_classifier_exists():
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier binary not found at {CLASSIFIER_PATH}"
    assert os.access(CLASSIFIER_PATH, os.X_OK), f"Classifier at {CLASSIFIER_PATH} is not executable"
    with open(CLASSIFIER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Classifier is not a compiled ELF executable"


def test_adversarial_corpus_clean():
    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    failed_clean = []

    for fpath in clean_files:
        result = subprocess.run([CLASSIFIER_PATH, fpath], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(fpath))

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean files rejected (exit code != 0): {failed_clean[:5]}..."


def test_adversarial_corpus_evil():
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    failed_evil = []

    for fpath in evil_files:
        result = subprocess.run([CLASSIFIER_PATH, fpath], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(fpath))

    assert not failed_evil, f"{len(failed_evil)} of {len(evil_files)} evil files bypassed (exit code != 1): {failed_evil[:5]}..."


def test_incoming_corpus_processing():
    assert os.path.isdir(VERIFIED_DIR), f"{VERIFIED_DIR} directory is missing"
    assert os.path.isdir(QUARANTINE_DIR), f"{QUARANTINE_DIR} directory is missing"

    clean_expected = []
    evil_expected = []

    for root, _, files in os.walk(INCOMING_CORPUS):
        for file in files:
            fpath = os.path.join(root, file)
            with open(fpath, "rb") as f:
                content = f.read()
            if SIGNATURE in content:
                evil_expected.append(fpath)
            else:
                clean_expected.append(fpath)

    verified_files = os.listdir(VERIFIED_DIR)
    quarantine_files = os.listdir(QUARANTINE_DIR)

    assert len(verified_files) == len(clean_expected), f"Expected {len(clean_expected)} files in verified repo, found {len(verified_files)}"
    assert len(quarantine_files) == len(evil_expected), f"Expected {len(evil_expected)} files in quarantine repo, found {len(quarantine_files)}"

    for clean_fpath in clean_expected:
        basename = os.path.basename(clean_fpath)
        verified_fpath = os.path.join(VERIFIED_DIR, basename)
        assert os.path.exists(verified_fpath), f"Missing verified file: {basename}"
        assert os.stat(clean_fpath).st_ino == os.stat(verified_fpath).st_ino, f"{verified_fpath} is not a hard link to {clean_fpath}"

    for evil_fpath in evil_expected:
        basename = os.path.basename(evil_fpath)
        quarantine_fpath = os.path.join(QUARANTINE_DIR, basename)
        assert os.path.islink(quarantine_fpath), f"{quarantine_fpath} is not a symbolic link"
        assert os.readlink(quarantine_fpath) == evil_fpath, f"{quarantine_fpath} does not point to {evil_fpath}"


def run_dynamic_case(binary, path, expected, audit_library):
    audit_log = f"/tmp/mmap-log-{uuid.uuid4().hex}"
    env = os.environ.copy()
    env["LD_PRELOAD"] = audit_library
    env["MMAP_AUDIT_TARGET"] = os.path.realpath(path)
    env["MMAP_AUDIT_LOG"] = audit_log

    process = subprocess.Popen([binary, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    pid = process.pid
    stdout, stderr = process.communicate(timeout=15)
    assert process.returncode == expected, (
        f"{binary} returned {process.returncode}, expected {expected}, for generated input; "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )

    mapped_by = []
    if os.path.exists(audit_log):
        with open(audit_log, "r", encoding="ascii") as f:
            mapped_by = [int(line.strip()) for line in f if line.strip()]
    assert pid in mapped_by, f"{binary} did not memory-map the input file {path}"


def test_generated_content_cases(tmp_path, video_signature, mmap_audit_library, rebuilt_classifier):
    cases = []
    sizes = [32, 63, 127, 511, 1024, 4096]

    for index in range(12):
        size = sizes[index % len(sizes)]
        data = bytearray(os.urandom(size))
        while video_signature in data:
            data = bytearray(os.urandom(size))
        path = tmp_path / uuid.uuid4().hex
        path.write_bytes(data)
        cases.append((str(path), 0))

    for index in range(12):
        size = sizes[index % len(sizes)]
        data = bytearray(os.urandom(size))
        positions = [0, size - len(video_signature), (size - len(video_signature)) // 2]
        position = positions[index % len(positions)]
        data[position:position + len(video_signature)] = video_signature
        path = tmp_path / uuid.uuid4().hex
        path.write_bytes(data)
        cases.append((str(path), 1))

    random.SystemRandom().shuffle(cases)
    for binary in (CLASSIFIER_PATH, rebuilt_classifier):
        for path, expected in cases:
            run_dynamic_case(binary, path, expected, mmap_audit_library)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
