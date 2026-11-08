#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile

API_PARSER_DIR = "/home/user/api_parser"
WORKSPACE_DIR = "/home/user/workspace"

EXPECTED_HEADER = """#ifndef HTTP_PARSER_H
#define HTTP_PARSER_H

typedef struct {
    char method[16];
    char path[256];
    int status;
} http_request_t;

void parse_request(const char *raw, http_request_t *req);

#endif
"""

EXPECTED_TEST = """#include "http_parser.h"
#include <stdio.h>
#include <string.h>

int main() {
    http_request_t req;
    parse_request("GET /api/v1/users?id=123 HTTP/1.1\\r\\n\\r\\n", &req);

    if (req.status == 1 && 
        strcmp(req.method, "GET") == 0 && 
        strcmp(req.path, "/api/v1/users?id=123") == 0) {
        printf("ALL TESTS PASSED\\n");
        return 0;
    }
    printf("TEST FAILED\\n");
    return 1;
}
"""

HARNESS = r'''#include "http_parser.h"
#include <stdio.h>
#include <string.h>

struct test_case {
    const char *raw;
    const char *method;
    const char *path;
};

int main(void) {
    const struct test_case cases[] = {
        {"GET /api/v1/users?id=123 HTTP/1.1\r\n\r\n", "GET", "/api/v1/users?id=123"},
        {"POST / HTTP/1.0\r\n", "POST", "/"},
        {"DELETE /items/42?force=yes HTTP/1.1\r\nHost: example\r\n\r\n", "DELETE", "/items/42?force=yes"},
        {"PATCH /a/b-c_d HTTP/2\r\n\r\n", "PATCH", "/a/b-c_d"}
    };
    unsigned long i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        http_request_t req;
        memset(&req, 0xA5, sizeof(req));
        parse_request(cases[i].raw, &req);
        if (req.status != 1 || strcmp(req.method, cases[i].method) != 0 ||
            strcmp(req.path, cases[i].path) != 0) {
            fprintf(stderr, "case %lu failed\n", i);
            return 1;
        }
    }
    return 0;
}
'''

def run(command, cwd=API_PARSER_DIR):
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30)

def test_directories_created():
    for d in ["src", "include", "tests"]:
        dir_path = os.path.join(API_PARSER_DIR, d)
        assert os.path.isdir(dir_path), f"Directory {dir_path} was not created."

def test_files_moved():
    expected_files = {
        "src/http_parser.c": "http_parser.c",
        "include/http_parser.h": "http_parser.h",
        "tests/test_http_parser.c": "test_http_parser.c"
    }
    for new_rel_path, old_name in expected_files.items():
        new_path = os.path.join(API_PARSER_DIR, new_rel_path)
        old_path = os.path.join(WORKSPACE_DIR, old_name)
        assert os.path.isfile(new_path), f"File {new_path} is missing. It should have been moved here."
        assert not os.path.exists(old_path), f"File {old_path} still exists. It should have been moved, not copied."

def test_protected_files_unmodified():
    with open(os.path.join(API_PARSER_DIR, "include/http_parser.h"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_HEADER, "http_parser.h was modified."
    with open(os.path.join(API_PARSER_DIR, "tests/test_http_parser.c"), encoding="utf-8") as f:
        assert f.read() == EXPECTED_TEST, "test_http_parser.c was modified."

def test_test_summary_content():
    summary_path = os.path.join(API_PARSER_DIR, "test_summary.txt")
    assert os.path.isfile(summary_path), f"File {summary_path} is missing. Did you run the 'test' target?"
    with open(summary_path, encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "ALL TESTS PASSED", f"Expected test_summary.txt to contain 'ALL TESTS PASSED', but got '{content}'."

def test_makefile_exists_and_works():
    makefile_path = os.path.join(API_PARSER_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}."

    clean_proc = run(["make", "clean"])
    assert clean_proc.returncode == 0, f"Failed to run 'make clean': {clean_proc.stderr}"
    assert not os.path.exists(os.path.join(API_PARSER_DIR, "libparser.a")), "'make clean' did not remove libparser.a"
    assert not os.path.exists(os.path.join(API_PARSER_DIR, "test_runner")), "'make clean' did not remove test_runner"
    assert not os.path.exists(os.path.join(API_PARSER_DIR, "test_summary.txt")), "'make clean' did not remove test_summary.txt"
    for root, _, files in os.walk(API_PARSER_DIR):
        assert not any(name.endswith(".o") for name in files), f"'make clean' left an object file in {root}"

    lib_proc = run(["make", "libparser.a"])
    assert lib_proc.returncode == 0, f"Failed to build libparser.a: {lib_proc.stderr}"
    library = os.path.join(API_PARSER_DIR, "libparser.a")
    assert os.path.isfile(library), "The libparser.a target did not create libparser.a."
    archive_proc = run(["ar", "t", library])
    assert archive_proc.returncode == 0 and archive_proc.stdout.strip(), "libparser.a is not a non-empty static archive."

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "behavior.c")
        source_runner = os.path.join(td, "source_runner")
        library_runner = os.path.join(td, "library_runner")
        with open(harness_path, "w", encoding="utf-8") as f:
            f.write(HARNESS)

        compile_source = run([
            "cc", "-std=c11", "-I", os.path.join(API_PARSER_DIR, "include"),
            harness_path, os.path.join(API_PARSER_DIR, "src/http_parser.c"), "-o", source_runner
        ])
        assert compile_source.returncode == 0, f"src/http_parser.c did not compile: {compile_source.stderr}"
        source_result = run([source_runner])
        assert source_result.returncode == 0, f"Parser source failed behavioral tests: {source_result.stderr}"

        compile_library = run([
            "cc", "-std=c11", "-I", os.path.join(API_PARSER_DIR, "include"),
            harness_path, library, "-o", library_runner
        ])
        assert compile_library.returncode == 0, f"libparser.a could not be linked: {compile_library.stderr}"
        library_result = run([library_runner])
        assert library_result.returncode == 0, f"libparser.a failed behavioral tests: {library_result.stderr}"

    runner_proc = run(["make", "test_runner"])
    assert runner_proc.returncode == 0, f"Failed to build test_runner: {runner_proc.stderr}"
    runner = os.path.join(API_PARSER_DIR, "test_runner")
    assert os.path.isfile(runner), "The test_runner target did not create test_runner."
    assert os.stat(runner).st_mode & stat.S_IXUSR, "test_runner is not executable."
    with open(runner, "rb") as f:
        assert f.read(4) == b"\x7fELF", "test_runner is not a compiled ELF executable."
    direct_result = run([runner])
    assert direct_result.returncode == 0, f"test_runner failed: {direct_result.stderr}"
    assert direct_result.stdout.strip() == "ALL TESTS PASSED", "test_runner produced unexpected output."

    clean_again = run(["make", "clean"])
    assert clean_again.returncode == 0, f"Second 'make clean' failed: {clean_again.stderr}"
    test_proc = run(["make", "test"])
    assert test_proc.returncode == 0, f"Failed to run 'make test': {test_proc.stderr}"
    assert os.path.isfile(library), "'make test' did not build libparser.a."
    assert os.path.isfile(runner), "'make test' did not build test_runner."
    summary_path = os.path.join(API_PARSER_DIR, "test_summary.txt")
    assert os.path.isfile(summary_path), "'make test' did not generate test_summary.txt"
    with open(summary_path, encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "ALL TESTS PASSED", f"After running 'make test', expected 'ALL TESTS PASSED' in summary, got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
