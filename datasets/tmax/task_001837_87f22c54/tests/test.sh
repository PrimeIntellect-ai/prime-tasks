#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/rename_hook.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static void record_success(const char *oldpath, const char *newpath, int result) {
    if (result == 0 && oldpath && newpath &&
        strcmp(oldpath, "/home/user/docs_final.json.tmp") == 0 &&
        strcmp(newpath, "/home/user/docs_final.json") == 0) {
        int fd = open("/tmp/doc_converter_rename.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            (void)write(fd, "OK\n", 3);
            close(fd);
        }
    }
}

int rename(const char *oldpath, const char *newpath) {
    typedef int (*rename_fn)(const char *, const char *);
    static rename_fn real_rename = NULL;
    if (!real_rename) real_rename = (rename_fn)dlsym(RTLD_NEXT, "rename");
    if (!real_rename) return -1;
    int result = real_rename(oldpath, newpath);
    record_success(oldpath, newpath, result);
    return result;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    typedef int (*renameat_fn)(int, const char *, int, const char *);
    static renameat_fn real_renameat = NULL;
    if (!real_renameat) real_renameat = (renameat_fn)dlsym(RTLD_NEXT, "renameat");
    if (!real_renameat) return -1;
    int result = real_renameat(olddirfd, oldpath, newdirfd, newpath);
    record_success(oldpath, newpath, result);
    return result;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    typedef int (*renameat2_fn)(int, const char *, int, const char *, unsigned int);
    static renameat2_fn real_renameat2 = NULL;
    if (!real_renameat2) real_renameat2 = (renameat2_fn)dlsym(RTLD_NEXT, "renameat2");
    if (!real_renameat2) return -1;
    int result = real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
    record_success(oldpath, newpath, result);
    return result;
}
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import pytest

JSON_PATH = "/home/user/docs_final.json"
TMP_PATH = "/home/user/docs_final.json.tmp"
PROJECT_PATH = "/home/user/doc_converter"
HOOK_PATH = "/tmp/rename_hook.so"
LOG_PATH = "/tmp/doc_converter_rename.log"


def test_json_output_exists_and_correct():
    json_path = "/home/user/docs_final.json"
    assert os.path.exists(json_path), f"JSON output file missing at {json_path}"
    assert os.path.isfile(json_path), f"{json_path} is not a file"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {json_path} as JSON: {e}")

    assert isinstance(data, list), "JSON root must be an array (list)"
    assert len(data) == 2, f"Expected 2 entries in JSON, found {len(data)}"

    assert data[0].get("title") == "Introduction to System", "Title mismatch for entry 1"
    assert data[0].get("author") == "Alice Writer", "Author mismatch for entry 1"
    assert data[0].get("body", "").strip() == "This is the introduction.\nIt spans multiple lines.", "Body mismatch for entry 1"

    assert data[1].get("title") == "Installation Guide", "Title mismatch for entry 2"
    assert data[1].get("author") == "Bob Coder", "Author mismatch for entry 2"
    assert data[1].get("body", "").strip() == "Step 1: Download\nStep 2: Install\nStep 3: Profit!", "Body mismatch for entry 2"


def test_rust_source_code_atomic_write():
    rs_path = "/home/user/doc_converter/src/main.rs"
    assert os.path.exists(rs_path), f"Rust source file missing at {rs_path}"
    assert os.path.isfile(rs_path), f"{rs_path} is not a file"

    with open(rs_path, 'r') as f:
        code = f.read()

    assert "rename" in code, "Code does not appear to use std::fs::rename for atomic writes. The word 'rename' was not found in main.rs."

    without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", code, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"\b(?:std\s*::\s*fs\s*::\s*|fs\s*::\s*)?rename\s*\(", without_comments), \
        "main.rs must contain an actual rename function call, not merely mention rename in a comment"


def assert_output(expected):
    assert os.path.isfile(JSON_PATH), "Program did not create docs_final.json"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, list), "JSON root must be an array"
    assert len(data) == len(expected), f"Expected {len(expected)} entries, found {len(data)}"
    for index, wanted in enumerate(expected):
        assert isinstance(data[index], dict), f"Entry {index + 1} must be an object"
        for key in ("title", "author", "body"):
            assert isinstance(data[index].get(key), str), f"Entry {index + 1} key {key} must be a string"
            assert data[index].get(key) == wanted[key], f"Entry {index + 1} {key} mismatch"


def run_converter(input_text, expected):
    for path in (TMP_PATH, LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(TMP_PATH, "w", encoding="utf-8") as f:
        f.write("stale temporary data")

    env = os.environ.copy()
    env["LD_PRELOAD"] = HOOK_PATH
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT_PATH, "Cargo.toml")],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=60,
    )
    assert result.returncode == 0, f"Converter execution failed:\n{result.stderr}"
    assert_output(expected)
    assert not os.path.exists(TMP_PATH), "Temporary output still exists after successful conversion"
    assert os.path.isfile(LOG_PATH), "No successful atomic rename of the required paths was observed"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        assert "OK" in f.read(), "No successful atomic rename of the required paths was observed"


def test_compile_execute_parser_and_atomic_rename():
    assert os.path.isfile(os.path.join(PROJECT_PATH, "Cargo.toml")), "Cargo.toml is missing"
    subprocess.run(
        ["cc", "-shared", "-fPIC", "-o", HOOK_PATH, "/tmp/rename_hook.c", "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", os.path.join(PROJECT_PATH, "Cargo.toml")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Rust project failed to compile:\n{build.stderr}"

    token = secrets.token_hex(10)
    expected_random = [
        {"title": f"Generated Title {token}", "author": f"Author {token[:8]}", "body": f"First line {token}\nSecond line"},
        {"title": f"Another {token[2:]}", "author": "Runtime Tester", "body": f"A body containing {token}\nand another line"},
        {"title": "Final Runtime Entry", "author": f"User {token[-8:]}", "body": f"Last body {token}"},
    ]
    random_input = "".join(
        f"==DOC==\nTitle: {entry['title']}\nAuthor: {entry['author']}\nBody:\n{entry['body']}\n"
        for entry in expected_random
    )
    run_converter(random_input, expected_random)

    with open("/home/user/raw_docs.txt", "r", encoding="utf-8") as f:
        fixture_input = f.read()
    fixture_expected = [
        {"title": "Introduction to System", "author": "Alice Writer", "body": "This is the introduction.\nIt spans multiple lines."},
        {"title": "Installation Guide", "author": "Bob Coder", "body": "Step 1: Download\nStep 2: Install\nStep 3: Profit!"},
    ]
    run_converter(fixture_input, fixture_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
