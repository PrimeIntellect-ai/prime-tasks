#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE = "/home/user/organizer"
SOURCE = "/home/user/organizer.c"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
PREFIX = "SECURE_ARCHIVE_"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=15, **kwargs)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "organizer must be a compiled native executable"


def test_clean_corpus():
    with tempfile.TemporaryDirectory() as out_dir:
        result = subprocess.run([EXECUTABLE, CLEAN_CORPUS, out_dir], capture_output=True)

        clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.json')]
        processed_count = 0
        expected_files = []

        for cf in clean_files:
            with open(os.path.join(CLEAN_CORPUS, cf), 'r') as f:
                data = json.load(f)
                expected_files.append((PREFIX + data["filename"], data["content"]))

        out_files = os.listdir(out_dir)
        missing = []

        for expected_name, expected_content in expected_files:
            if expected_name not in out_files:
                missing.append(expected_name)
            else:
                with open(os.path.join(out_dir, expected_name), 'r') as f:
                    content = f.read()
                    assert content == expected_content, f"Content mismatch for {expected_name}"
                processed_count += 1

        assert not missing, f"{len(missing)} of {len(clean_files)} clean files modified/missing. Missing expected outputs: {missing}"
        assert processed_count == len(clean_files), f"Expected {len(clean_files)} clean files processed, got {processed_count}"


def test_evil_corpus():
    with tempfile.TemporaryDirectory() as out_dir:
        result = subprocess.run([EXECUTABLE, EVIL_CORPUS, out_dir], capture_output=True)

        evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.json')]
        out_files = [f for f in os.listdir(out_dir) if not f.startswith('.')]

        assert not out_files, f"{len(out_files)} of {len(evil_files)} evil bypassed. Files written to output directory: {out_files}"


@pytest.fixture(scope="session")
def built_program(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    build_dir = tmp_path_factory.mktemp("build")
    output = build_dir / "organizer-from-source"
    result = run(["gcc", "-std=c11", "-O2", SOURCE, "-o", str(output), "-ljson-c"])
    assert result.returncode == 0, (
        "organizer.c did not compile as C:\n" + result.stderr.decode(errors="replace")
    )
    return str(output)


@pytest.fixture(scope="session")
def atomic_probe(tmp_path_factory):
    probe_dir = tmp_path_factory.mktemp("probe")
    source = probe_dir / "probe.c"
    library = probe_dir / "probe.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void record(const char *kind, const char *a, const char *b, int rc) {
    const char *log = getenv("ORGANIZER_ATOMIC_LOG");
    if (!log) return;
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    dprintf(fd, "%s\t%s\t%s\t%d\n", kind, a ? a : "", b ? b : "", rc);
    close(fd);
}

int mkstemp(char *template) {
    static int (*real_fn)(char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "mkstemp");
    int rc = real_fn(template);
    record("mkstemp", template, "", rc);
    return rc;
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_fn)(const char *, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "rename");
    int rc = real_fn(oldpath, newpath);
    record("rename", oldpath, newpath, rc);
    return rc;
}
''')
    result = run(["gcc", "-shared", "-fPIC", str(source), "-o", str(library), "-ldl"])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return str(library)


def execute_with_probe(program, input_dir, output_dir, probe, log_path):
    env = os.environ.copy()
    env["LD_PRELOAD"] = probe
    env["ORGANIZER_ATOMIC_LOG"] = str(log_path)
    return run([program, str(input_dir), str(output_dir)], env=env)


def assert_atomic_events(log_path, output_dir, expected_names):
    assert log_path.exists(), "No mkstemp/rename activity was observed"
    events = [line.split("\t") for line in log_path.read_text().splitlines()]
    temps = {
        os.path.realpath(parts[1])
        for parts in events
        if len(parts) == 4 and parts[0] == "mkstemp" and int(parts[3]) >= 0
    }
    renames = [
        (os.path.realpath(parts[1]), os.path.realpath(parts[2]))
        for parts in events
        if len(parts) == 4 and parts[0] == "rename" and int(parts[3]) == 0
    ]
    out_real = os.path.realpath(output_dir)
    assert temps, "Valid files were not written using mkstemp()"
    for temp_path in temps:
        assert os.path.dirname(temp_path) == out_real, "mkstemp temporary file was not inside output_dir"
    for name in expected_names:
        destination = os.path.realpath(os.path.join(output_dir, name))
        assert any(src in temps and dst == destination for src, dst in renames), (
            f"{name} was not atomically installed by rename() from an mkstemp file"
        )


@pytest.mark.parametrize("which", ["submitted", "rebuilt"])
def test_randomized_valid_json_and_atomic_writes(which, built_program, atomic_probe, tmp_path):
    program = EXECUTABLE if which == "submitted" else built_program
    token = secrets.token_hex(12)
    input_dir = tmp_path / f"input-{which}"
    output_dir = tmp_path / f"output-{which}"
    input_dir.mkdir()
    output_dir.mkdir()

    records = [
        (f"alpha_{token}.log", f"random content {token}"),
        (f"space name {token}.txt", "quotes: \"x\" and newline:\nsecond line"),
        (f"unicode_{token}_é.log", "snowman ☃ and JSON escapes \\ /"),
        (f"single.{token}", ""),
        (f"many.dots.{token}.txt", "final payload"),
    ]
    for index, (filename, content) in enumerate(records):
        payload = {"content": content, "filename": filename}
        (input_dir / f"random-{index}.json").write_text(
            json.dumps(payload, ensure_ascii=(index % 2 == 0)), encoding="utf-8"
        )
    (input_dir / "ignored.txt").write_text("not json")

    log_path = tmp_path / f"atomic-{which}.log"
    result = execute_with_probe(program, input_dir, output_dir, atomic_probe, log_path)
    assert result.returncode == 0, result.stderr.decode(errors="replace")

    expected = {PREFIX + name: content for name, content in records}
    assert set(os.listdir(output_dir)) == set(expected), "Unexpected or missing randomized outputs"
    for name, content in expected.items():
        assert (output_dir / name).read_text(encoding="utf-8") == content
    assert_atomic_events(log_path, output_dir, expected.keys())


@pytest.mark.parametrize("which", ["submitted", "rebuilt"])
def test_randomized_malicious_and_invalid_inputs(which, built_program, tmp_path):
    program = EXECUTABLE if which == "submitted" else built_program
    token = secrets.token_hex(12)
    cases = [
        {"filename": f"../escaped_{token}", "content": "bad"},
        {"filename": f"dir/sub_{token}", "content": "bad"},
        {"filename": f"dir\\sub_{token}", "content": "bad"},
        {"filename": f"safe..bad_{token}", "content": "bad"},
        {"filename": f"/tmp/absolute_{token}", "content": "bad"},
        {"filename": f"..\\windows_{token}", "content": "bad"},
    ]
    malformed = [
        '{"filename":"x","content":',
        json.dumps({"filename": "missing-content"}),
        json.dumps({"filename": 7, "content": "bad"}),
        json.dumps({"filename": "bad", "content": ["not", "string"]}),
    ]

    for index, payload in enumerate([json.dumps(x) for x in cases] + malformed):
        case_dir = tmp_path / f"bad-{which}-{index}"
        out_dir = tmp_path / f"bad-out-{which}-{index}"
        case_dir.mkdir()
        out_dir.mkdir()
        (case_dir / "case.json").write_text(payload, encoding="utf-8")
        result = run([program, str(case_dir), str(out_dir)])
        assert os.listdir(out_dir) == [], f"Rejected case {index} produced output"
        assert result.returncode != 0 or result.stderr, (
            f"Rejected case {index} produced neither a warning nor non-zero status"
        )

    assert not (tmp_path / f"escaped_{token}").exists()
    assert not Path(f"/tmp/absolute_{token}").exists()


@pytest.mark.parametrize("program_kind", ["submitted", "rebuilt"])
def test_exact_argument_count(program_kind, built_program):
    program = EXECUTABLE if program_kind == "submitted" else built_program
    assert run([program]).returncode != 0
    assert run([program, "one", "two", "three"]).returncode != 0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
