#!/bin/bash
mkdir -p /logs/verifier

cat << 'C_EOF' > /tmp/rename_logger.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void log_rename(const char *oldpath, const char *newpath) {
    const char *logpath = getenv("SAN_RENAME_LOG");
    if (!logpath || !*logpath) return;

    char oldbuf[PATH_MAX];
    char newbuf[PATH_MAX];
    const char *oldout = realpath(oldpath, oldbuf) ? oldbuf : oldpath;
    const char *newout = realpath(newpath, newbuf) ? newbuf : newpath;

    int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    dprintf(fd, "%s\t%s\n", oldout, newout);
    close(fd);
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *) = NULL;
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");

    char oldbuf[PATH_MAX];
    const char *saved_old = realpath(oldpath, oldbuf) ? oldbuf : oldpath;
    char oldcopy[PATH_MAX];
    snprintf(oldcopy, sizeof(oldcopy), "%s", saved_old);

    int result = real_rename(oldpath, newpath);
    if (result == 0) log_rename(oldcopy, newpath);
    return result;
}
C_EOF

gcc -shared -fPIC -o /tmp/rename_logger.so /tmp/rename_logger.c -ldl >/tmp/rename_logger_build.log 2>&1
LOGGER_STATUS=$?

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import os
import pathlib
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/sanitize.py"
BUILDER_PATH = "/app/doc_builder"
CLEAN_CORPUS = "/home/user/corpus/clean"
EVIL_CORPUS = "/home/user/corpus/evil"
ASSET_DIR = "/home/user/docs/assets"
LOGGER = "/tmp/rename_logger.so"


def expected_output(data):
    pieces = []
    for offset in range(0, len(data), 2048):
        result = subprocess.run(
            [BUILDER_PATH], input=data[offset:offset + 2048],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
        pieces.append(result.stdout)
    return b"".join(pieces)


def invoke(input_path, outdir, timeout=10):
    log_path = os.path.join(outdir, ".rename-log")
    env = os.environ.copy()
    env["LD_PRELOAD"] = LOGGER
    env["SAN_RENAME_LOG"] = log_path
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "--input", input_path, "--outdir", outdir],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=timeout
    )
    events = []
    if os.path.exists(log_path):
        with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                fields = line.rstrip("\n").split("\t", 1)
                if len(fields) == 2:
                    events.append(tuple(fields))
        os.unlink(log_path)
    return result, events


def assert_clean(input_path, outdir):
    name = os.path.basename(input_path)
    output_path = os.path.join(outdir, name + ".html")
    legacy_path = os.path.join(outdir, os.path.splitext(name)[0] + ".html")
    source = pathlib.Path(input_path).read_bytes()

    result, events = invoke(input_path, outdir)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    assert os.path.isfile(output_path), f"missing output {output_path}"
    assert pathlib.Path(output_path).read_bytes() == expected_output(source)
    if legacy_path != output_path:
        assert not os.path.exists(legacy_path), f"wrote incorrect stem-based output {legacy_path}"

    destination = os.path.realpath(output_path)
    matching = [(old, new) for old, new in events if new == destination and old != new]
    assert matching, "the final output was not installed by a successful atomic rename"
    assert any(os.path.dirname(old) == os.path.dirname(destination) for old, _ in matching), (
        "temporary output and destination must be in the same directory"
    )


def assert_malicious(input_path):
    with tempfile.TemporaryDirectory() as outdir:
        result, _ = invoke(input_path, outdir)
        assert result.returncode == 1, (
            f"malicious input returned {result.returncode}: "
            f"{result.stderr.decode('utf-8', 'replace')}"
        )
        assert result.stderr, "malicious input must print an error to stderr"
        assert os.listdir(outdir) == [], "malicious input left an output or temporary file"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"
    assert os.path.isfile(BUILDER_PATH) and os.access(BUILDER_PATH, os.X_OK)
    assert os.path.isfile(LOGGER), "rename instrumentation was not built"


def test_evil_corpus():
    evil_files = sorted(
        f for f in os.listdir(EVIL_CORPUS)
        if os.path.isfile(os.path.join(EVIL_CORPUS, f)) and f != "evil_4.md"
    )
    assert evil_files, "Evil corpus is empty."
    for evil_file in evil_files:
        assert_malicious(os.path.join(EVIL_CORPUS, evil_file))


def test_clean_corpus_and_exact_compiler_output():
    clean_files = sorted(
        f for f in os.listdir(CLEAN_CORPUS)
        if os.path.isfile(os.path.join(CLEAN_CORPUS, f))
    )
    assert clean_files, "Clean corpus is empty."
    with tempfile.TemporaryDirectory() as outdir:
        for clean_file in clean_files:
            assert_clean(os.path.join(CLEAN_CORPUS, clean_file), outdir)


def test_generated_clean_inputs_chunking_and_safe_include():
    token = secrets.token_hex(8)
    target = os.path.join(ASSET_DIR, f"target_{token}.txt")
    link = os.path.join(ASSET_DIR, f"safe_link_{token}.txt")
    pathlib.Path(target).write_text("safe generated asset\n", encoding="utf-8")
    os.symlink(target, link)

    try:
        cases = [
            b"small *formatted* document\n",
            b"A" * 2048,
            b"A" * 2047 + b"*cross-boundary*" + b"B" * 2070,
            ("é" * 1100 + " *unicode* " + "Z" * 2200).encode("utf-8"),
            (f"safe include [[INCLUDE_ASSET: {os.path.basename(link)}]] and *text*\n").encode(),
        ]
        with tempfile.TemporaryDirectory() as workdir:
            for index, data in enumerate(cases):
                input_path = os.path.join(workdir, f"random_{token}_{index}.markdown")
                pathlib.Path(input_path).write_bytes(data)
                with tempfile.TemporaryDirectory() as outdir:
                    assert_clean(input_path, outdir)
    finally:
        if os.path.lexists(link):
            os.unlink(link)
        if os.path.exists(target):
            os.unlink(target)


def test_generated_malicious_inputs_are_content_driven():
    token = secrets.token_hex(8)
    outside = os.path.join("/tmp", f"outside_{token}.txt")
    outside_link = os.path.join(ASSET_DIR, f"outside_link_{token}.txt")
    loop_a = os.path.join(ASSET_DIR, f"loop_a_{token}.txt")
    loop_b = os.path.join(ASSET_DIR, f"loop_b_{token}.txt")
    pathlib.Path(outside).write_text("secret\n", encoding="utf-8")
    os.symlink(outside, outside_link)
    os.symlink(loop_b, loop_a)
    os.symlink(loop_a, loop_b)

    try:
        payloads = [
            b"random document [[INCLUDE_ASSET: ../../../../../etc/passwd]]\n",
            f"random document [[INCLUDE_ASSET: {os.path.basename(outside_link)}]]\n".encode(),
            f"random document [[INCLUDE_ASSET: {os.path.basename(loop_a)}]]\n".encode(),
        ]
        with tempfile.TemporaryDirectory(prefix="ordinary-inputs-") as workdir:
            for index, payload in enumerate(payloads):
                input_path = os.path.join(workdir, f"submission_{token}_{index}.txt")
                pathlib.Path(input_path).write_bytes(payload)
                assert_malicious(input_path)
    finally:
        for path in (outside_link, loop_a, loop_b):
            if os.path.lexists(path):
                os.unlink(path)
        if os.path.exists(outside):
            os.unlink(outside)


def test_atomic_writes_ast():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    tree = ast.parse(source)
    found_atomic = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if node.func.attr in ("rename", "replace") and getattr(node.func.value, "id", "") == "os":
                    found_atomic = True
                    break
            elif isinstance(node.func, ast.Name):
                if node.func.id in ("rename", "replace"):
                    found_atomic = True
                    break
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                if "tempfile" in alias.name:
                    found_atomic = True
                    break
    assert found_atomic, "Could not verify atomic writes: no os.rename/os.replace or tempfile usage found in AST."
PY_EOF

if [ "$LOGGER_STATUS" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
