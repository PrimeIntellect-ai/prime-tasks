#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import struct
import subprocess
import tempfile
import uuid

import pytest

PIPELINE = "/home/user/pipeline"
PARSER = os.path.join(PIPELINE, "parser")
SOURCE = os.path.join(PIPELINE, "parser.c")
SCRIPT = os.path.join(PIPELINE, "process_logs.sh")
RESULTS = os.path.join(PIPELINE, "results.txt")
ERROR_LOG = os.path.join(PIPELINE, "error.log")
REPORT = "/home/user/final_report.txt"

EXPECTED_INITIAL_LINES = [
    "Processed 2 records from /home/user/uploads/valid1.log",
    "Processed 3 records from /home/user/uploads/file with spaces.log",
    "Corrupted input: /home/user/uploads/corrupt.log",
    "Corrupted input: /home/user/uploads/massive.log",
]


def run(command, **kwargs):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=10, **kwargs)


def write_log(path, n, payload=None, magic=b"LOG1"):
    if payload is None:
        payload = b"X" * (max(n, 0) * 16)
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("=i", n))
        f.write(payload)


def assert_clean_exit(proc, expected=None):
    assert proc.returncode >= 0, f"Process terminated by signal {-proc.returncode}: {proc.stderr}"
    if expected is not None:
        assert proc.returncode == expected, (
            f"Expected exit status {expected}, got {proc.returncode}; "
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        )


@pytest.fixture(scope="session")
def fresh_parser(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "parser"
    proc = run(["gcc", "-o", str(output), SOURCE], cwd=PIPELINE)
    assert proc.returncode == 0, f"parser.c does not compile with gcc -o parser parser.c: {proc.stderr}"
    assert output.is_file()
    return str(output)


@pytest.fixture(scope="session")
def malloc_failure_library(tmp_path_factory):
    directory = tmp_path_factory.mktemp("malloc_fail")
    source = directory / "failmalloc.c"
    library = directory / "failmalloc.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdlib.h>

static void *(*real_malloc)(size_t);
static void *(*real_calloc)(size_t, size_t);
static void *(*real_realloc)(void *, size_t);

static size_t target_size(void) {
    const char *value = getenv("VERIFIER_FAIL_SIZE");
    return value ? (size_t)strtoull(value, NULL, 10) : 0;
}

void *malloc(size_t size) {
    if (!real_malloc) real_malloc = dlsym(RTLD_NEXT, "malloc");
    if (target_size() && size == target_size()) return NULL;
    return real_malloc(size);
}

void *calloc(size_t count, size_t size) {
    if (!real_calloc) real_calloc = dlsym(RTLD_NEXT, "calloc");
    if (target_size() && count != 0 && size <= (size_t)-1 / count && count * size == target_size()) return NULL;
    return real_calloc(count, size);
}

void *realloc(void *ptr, size_t size) {
    if (!real_realloc) real_realloc = dlsym(RTLD_NEXT, "realloc");
    if (target_size() && size == target_size()) return NULL;
    return real_realloc(ptr, size);
}
''')
    proc = run(["gcc", "-shared", "-fPIC", "-o", str(library), str(source), "-ldl"])
    assert proc.returncode == 0, f"Could not build allocation-failure test helper: {proc.stderr}"
    return str(library)


def test_final_report_exists():
    assert os.path.isfile(REPORT), "The file /home/user/final_report.txt does not exist."


def test_final_report_contents_and_copy():
    with open(REPORT, "r") as f:
        content = f.read()

    for line in EXPECTED_INITIAL_LINES:
        assert line in content, f"Expected output not found in /home/user/final_report.txt: '{line}'"

    assert os.path.isfile(RESULTS), "The pipeline results.txt file is missing."
    with open(RESULTS, "r") as f:
        results_content = f.read()

    assert content == results_content, "final_report.txt is not an exact copy of results.txt."
    assert collections.Counter(content.splitlines()) == collections.Counter(EXPECTED_INITIAL_LINES), (
        "The report contains missing, duplicate, or stale pipeline output."
    )


def test_no_segfaults_in_error_log():
    if os.path.isfile(ERROR_LOG):
        with open(ERROR_LOG, "r") as f:
            content = f.read().lower()
            assert "segmentation fault" not in content, "A Segmentation Fault was recorded in error.log."
            assert "segfault" not in content, "A Segfault was recorded in error.log."


def test_parser_c_fixed():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "Corrupted input:" in content, "The C code does not seem to print 'Corrupted input:' as requested."
    assert "10000" in content, "The C code does not seem to check the upper bound of 10000 for N."


def test_shell_script_fixed():
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} is missing."
    with open(SCRIPT, "r") as f:
        content = f.read()

    assert "$(ls" not in content, "The shell script still uses the buggy `$(ls ...)` construct which breaks on spaces."
    assert os.access(SCRIPT, os.X_OK), "The pipeline shell script is not executable."


def test_installed_parser_is_executable_elf():
    assert os.path.isfile(PARSER), "The rebuilt parser executable is missing."
    assert os.access(PARSER, os.X_OK), "The rebuilt parser is not executable."
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The parser is not a compiled executable."


@pytest.mark.parametrize("which", ["installed", "fresh"])
def test_parser_behavior_on_derived_inputs(which, fresh_parser, tmp_path):
    executable = PARSER if which == "installed" else fresh_parser
    token = uuid.uuid4().hex

    valid = tmp_path / f"valid {token}.log"
    write_log(valid, 7)
    proc = run([executable, str(valid)])
    assert_clean_exit(proc, 0)
    assert proc.stdout.strip() == f"Processed 7 records from {valid}"

    for count in (-13, 10001, 57321):
        bad = tmp_path / f"bad count {count} {token}.log"
        write_log(bad, count, b"payload")
        proc = run([executable, str(bad)])
        assert_clean_exit(proc, 1)
        assert proc.stdout.strip() == f"Corrupted input: {bad}"

    truncated_records = tmp_path / f"truncated records {token}.log"
    write_log(truncated_records, 8, b"too short")
    proc = run([executable, str(truncated_records)])
    assert_clean_exit(proc)
    assert proc.returncode != 0, "A truncated record section was reported as successfully processed."

    short_header = tmp_path / f"short header {token}.log"
    short_header.write_bytes(b"LO")
    proc = run([executable, str(short_header)])
    assert_clean_exit(proc)
    assert proc.returncode != 0

    missing_count = tmp_path / f"missing count {token}.log"
    missing_count.write_bytes(b"LOG1\x01")
    proc = run([executable, str(missing_count)])
    assert_clean_exit(proc)
    assert proc.returncode != 0


@pytest.mark.parametrize("which", ["installed", "fresh"])
def test_allocation_failure_is_handled(which, fresh_parser, malloc_failure_library, tmp_path):
    executable = PARSER if which == "installed" else fresh_parser
    count = 17
    path = tmp_path / f"allocation failure {uuid.uuid4().hex}.log"
    write_log(path, count)
    env = os.environ.copy()
    env["LD_PRELOAD"] = malloc_failure_library
    env["VERIFIER_FAIL_SIZE"] = str(count * 16)
    proc = run([executable, str(path)], env=env)
    assert_clean_exit(proc, 1)
    assert proc.stdout.strip() == f"Corrupted input: {path}"


def test_pipeline_really_processes_random_files_with_spaces():
    uploads = "/home/user/uploads"
    backup = f"/tmp/uploads-backup-{uuid.uuid4().hex}"
    saved_outputs = {}

    for path in (RESULTS, ERROR_LOG):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved_outputs[path] = f.read()
        else:
            saved_outputs[path] = None

    os.rename(uploads, backup)
    os.mkdir(uploads)
    try:
        token = uuid.uuid4().hex
        cases = [
            (f"first valid {token}.log", 4),
            (f"second valid file {token}.log", 9),
            (f"negative count {token}.log", -5),
            (f"oversized count {token}.log", 10002),
        ]
        for name, count in cases:
            write_log(os.path.join(uploads, name), count, b"Z" * (max(count, 0) * 16 if count <= 10000 else 16))

        for path in (RESULTS, ERROR_LOG):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        proc = run([SCRIPT])
        assert proc.returncode >= 0, f"Pipeline terminated by signal {-proc.returncode}"
        assert os.path.isfile(RESULTS), "Running process_logs.sh did not create results.txt."

        with open(RESULTS, "r") as f:
            actual = f.read().splitlines()

        expected = []
        for name, count in cases:
            path = os.path.join(uploads, name)
            if 0 <= count <= 10000:
                expected.append(f"Processed {count} records from {path}")
            else:
                expected.append(f"Corrupted input: {path}")

        assert collections.Counter(actual) == collections.Counter(expected), (
            f"Pipeline output did not come from processing all randomized files. "
            f"Expected {expected!r}, got {actual!r}"
        )

        if os.path.isfile(ERROR_LOG):
            with open(ERROR_LOG, "r") as f:
                errors = f.read().lower()
            assert "segmentation fault" not in errors and "segfault" not in errors
    finally:
        if os.path.isdir(uploads):
            shutil.rmtree(uploads)
        os.rename(backup, uploads)
        for path, data in saved_outputs.items():
            if data is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
