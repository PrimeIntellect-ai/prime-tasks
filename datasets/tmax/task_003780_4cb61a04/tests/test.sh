#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import tarfile
import zipfile


def test_extracted_files_exist():
    expected_files = ["doc1.txt", "doc2.txt", "doc3.txt"]
    for f in expected_files:
        path = os.path.join("/home/user/extracted_zips", f)
        assert os.path.isfile(path), f"Extracted file missing: {path}"


def test_doc_map_conf():
    conf_path = "/home/user/doc_map.conf"
    assert os.path.isfile(conf_path), f"Configuration file missing: {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    expected_mappings = [
        "/home/user/extracted_zips/doc1.txt=/home/user/final_docs/doc1.txt",
        "/home/user/extracted_zips/doc2.txt=/home/user/final_docs/doc2.txt",
        "/home/user/extracted_zips/doc3.txt=/home/user/final_docs/doc3.txt"
    ]

    for mapping in expected_mappings:
        assert mapping in content, f"Expected mapping '{mapping}' not found in {conf_path}"


def test_transformer_c_code():
    c_path = "/home/user/transformer.c"
    assert os.path.isfile(c_path), f"C program missing: {c_path}"

    with open(c_path, "r") as f:
        content = f.read()

    assert "mmap" in content, "C program does not use 'mmap'"
    assert "rename" in content, "C program does not use 'rename'"


def test_final_docs_content():
    expected_contents = {
        "doc1.txt": "Title: API v1\nStatus: [FINAL]\nThis is the [FINAL] documentation for API v1.\n",
        "doc2.txt": "Title: Architecture\nThis architecture document is currently a [FINAL].\n",
        "doc3.txt": "[FINAL] Release Notes\nNo major changes.\n"
    }

    for filename, expected_text in expected_contents.items():
        path = os.path.join("/home/user/final_docs", filename)
        assert os.path.isfile(path), f"Final document missing: {path}"

        with open(path, "r") as f:
            content = f.read()

        assert "[DRAFT]" not in content, f"Found '[DRAFT]' in {path}, should be replaced."
        assert "[FINAL]" in content, f"Expected '[FINAL]' not found in {path}."
        assert content.strip() == expected_text.strip(), f"Content mismatch in {path}"


def test_pipeline_state_is_derived_from_archive():
    archive = "/home/user/raw_docs.tar.gz"
    expected_texts = {}
    expected_zip_paths = []

    with tarfile.open(archive, "r:gz") as tf:
        zip_members = [m for m in tf.getmembers() if m.isfile() and m.name.lower().endswith(".zip")]
        assert zip_members, "Raw archive contains no zip files"
        for member in zip_members:
            payload = tf.extractfile(member).read()
            extracted_zip = os.path.join("/home/user/extracted", member.name)
            expected_zip_paths.append(extracted_zip)
            assert os.path.isfile(extracted_zip), f"Archive zip was not extracted: {extracted_zip}"
            with open(extracted_zip, "rb") as f:
                assert f.read() == payload, f"Extracted zip differs from archive member: {member.name}"

            with zipfile.ZipFile(io.BytesIO(payload)) as zf:
                for info in zf.infolist():
                    if not info.is_dir() and info.filename.lower().endswith(".txt"):
                        name = os.path.basename(info.filename)
                        assert name not in expected_texts, f"Duplicate text basename in fixture: {name}"
                        expected_texts[name] = zf.read(info)

    assert expected_texts, "Nested zip files contain no text documents"
    expected_mappings = set()
    for name, raw in expected_texts.items():
        input_path = os.path.join("/home/user/extracted_zips", name)
        output_path = os.path.join("/home/user/final_docs", name)
        assert os.path.isfile(input_path), f"Nested text file was not extracted: {input_path}"
        with open(input_path, "rb") as f:
            assert f.read() == raw, f"Extracted text differs from nested zip member: {name}"
        expected_mappings.add(f"{input_path}={output_path}")
        with open(output_path, "rb") as f:
            assert f.read() == raw.replace(b"[DRAFT]", b"[FINAL]"), f"Incorrect transformed output: {name}"

    with open("/home/user/doc_map.conf", "r", encoding="utf-8") as f:
        actual_mappings = {line.strip() for line in f if line.strip()}
    assert actual_mappings == expected_mappings, "Configuration mappings do not match archive-derived text files"
TEST_EOF

cat << 'TRACE_EOF' > /tmp/trace_calls.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static void append_log(const char *line) {
    const char *path = getenv("TRACE_LOG");
    if (!path) return;
    int fd = (int)syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, line, strlen(line));
        syscall(SYS_close, fd);
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED) {
        char linkpath[64], target[PATH_MAX], line[PATH_MAX + 16];
        snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(linkpath, target, sizeof(target) - 1);
        if (n >= 0) {
            target[n] = '\0';
            const char *wanted = getenv("TRACE_INPUT");
            if (wanted && strcmp(target, wanted) == 0) {
                snprintf(line, sizeof(line), "MMAP|%s\n", target);
                append_log(line);
            }
        }
    }
    return result;
}

static void snapshot_file(const char *path) {
    const char *snapshot = getenv("TRACE_SNAPSHOT");
    if (!snapshot) return;
    int in = (int)syscall(SYS_openat, AT_FDCWD, path, O_RDONLY, 0);
    int out = (int)syscall(SYS_openat, AT_FDCWD, snapshot, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (in < 0 || out < 0) {
        if (in >= 0) syscall(SYS_close, in);
        if (out >= 0) syscall(SYS_close, out);
        return;
    }
    char buf[4096];
    ssize_t n;
    while ((n = syscall(SYS_read, in, buf, sizeof(buf))) > 0) {
        char *p = buf;
        ssize_t left = n;
        while (left > 0) {
            ssize_t w = syscall(SYS_write, out, p, left);
            if (w <= 0) break;
            p += w;
            left -= w;
        }
    }
    syscall(SYS_close, in);
    syscall(SYS_close, out);
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    int rc = real_rename(oldpath, newpath);
    if (rc == 0) {
        char line[PATH_MAX * 2 + 16];
        snprintf(line, sizeof(line), "RENAME|%s|%s\n", oldpath, newpath);
        append_log(line);
        const char *wanted = getenv("TRACE_OUTPUT");
        if (wanted && strcmp(newpath, wanted) == 0) snapshot_file(newpath);
    }
    return rc;
}
TRACE_EOF

behavioral_test() {
    gcc /home/user/transformer.c -o /tmp/submitted_transformer || return 1
    gcc -shared -fPIC /tmp/trace_calls.c -o /tmp/trace_calls.so -ldl || return 1

    DYN="verifier_$(python3 -c 'import secrets; print(secrets.token_hex(12))').txt"
    export DYN
    export TRACE_INPUT="/home/user/extracted_zips/$DYN"
    export TRACE_OUTPUT="/home/user/final_docs/$DYN"
    export TRACE_LOG=/tmp/transformer_trace.log
    export TRACE_SNAPSHOT=/tmp/rename_snapshot.bin
    rm -f "$TRACE_OUTPUT" "$TRACE_LOG" "$TRACE_SNAPSHOT"

    python3 - << 'PY' || return 1
import os, secrets
name = os.environ["DYN"]
token = secrets.token_hex(24)
data = (f"Generated {token}\n[DRAFT] alpha {token}\nbeta [DRAFT] gamma\n").encode()
with open(os.environ["TRACE_INPUT"], "wb") as f:
    f.write(data)
with open("/tmp/dynamic_expected.bin", "wb") as f:
    f.write(data.replace(b"[DRAFT]", b"[FINAL]"))
with open("/home/user/doc_map.conf", "w", encoding="utf-8") as f:
    f.write(f"{os.environ['TRACE_INPUT']}={os.environ['TRACE_OUTPUT']}\n")
PY

    (cd /home/user && timeout 15s env LD_PRELOAD=/tmp/trace_calls.so /tmp/submitted_transformer) || return 1

    python3 - << 'PY' || return 1
import os
with open("/tmp/dynamic_expected.bin", "rb") as f:
    expected = f.read()
with open(os.environ["TRACE_OUTPUT"], "rb") as f:
    assert f.read() == expected, "Compiled transformer produced incorrect content for generated input"
with open(os.environ["TRACE_SNAPSHOT"], "rb") as f:
    assert f.read() == expected, "Correct content was not present at the successful rename"
with open(os.environ["TRACE_LOG"], "r", encoding="utf-8") as f:
    lines = f.read().splitlines()
assert f"MMAP|{os.environ['TRACE_INPUT']}" in lines, "Generated input was not successfully memory-mapped"
renames = [line.split("|", 2) for line in lines if line.startswith("RENAME|")]
valid = False
for _, old, new in renames:
    if new == os.environ["TRACE_OUTPUT"]:
        old_abs = os.path.abspath(old)
        if os.path.dirname(old_abs) == "/home/user/final_docs" and os.path.basename(old_abs).endswith(".tmp"):
            valid = True
assert valid, "Output was not atomically renamed from a .tmp file in final_docs"
PY
}

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && behavioral_test; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
