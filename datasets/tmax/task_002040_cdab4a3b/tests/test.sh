#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/filter_backup"
LIBDIR = "/app/libgraphbackup-1.2.0/build/lib"
LIBRARY = os.path.join(LIBDIR, "libgraphbackup.so")
SOURCE = "/home/user/filter_backup.cpp"
REBUILT = "/tmp/filter_backup_rebuilt"


def run_filter(executable, path, extra_env=None):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LIBDIR + ":" + env.get("LD_LIBRARY_PATH", "")
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [executable, path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=10,
    ).returncode


@pytest.fixture(scope="session", autouse=True)
def validate_build_and_source():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}."
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}."
    assert os.path.isfile(LIBRARY), "Installed libgraphbackup.so not found."
    assert os.path.isfile("/app/libgraphbackup-1.2.0/build/include/graphbackup.h"), "Installed header not found."

    makefile = open("/app/libgraphbackup-1.2.0/Makefile", encoding="utf-8").read()
    assert "-shared" in makefile, "Makefile does not build a shared library."
    assert not re.search(r"^\s*CXX\s*[:?+]?=\s*gcc\s*$", makefile, re.MULTILINE), "Makefile still uses gcc as its C++ linker."

    lib_header = subprocess.run(["readelf", "-h", LIBRARY], capture_output=True, text=True)
    assert lib_header.returncode == 0 and "DYN (Shared object file)" in lib_header.stdout, "Installed library is not a shared object."

    exe_header = subprocess.run(["readelf", "-h", EXECUTABLE], capture_output=True, text=True)
    assert exe_header.returncode == 0, "filter_backup is not an ELF executable."
    dynamic = subprocess.run(["readelf", "-d", EXECUTABLE], capture_output=True, text=True)
    assert dynamic.returncode == 0 and "libgraphbackup.so" in dynamic.stdout, "filter_backup is not dynamically linked to libgraphbackup."
    symbols = subprocess.run(["nm", "-D", "-C", EXECUTABLE], capture_output=True, text=True)
    assert symbols.returncode == 0 and re.search(r"\bU\s+extract_queries\(", symbols.stdout), "filter_backup does not import extract_queries."

    built = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-I/app/libgraphbackup-1.2.0/build/include", "-L" + LIBDIR,
         "-lgraphbackup", "-Wl,-rpath," + LIBDIR, "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert built.returncode == 0, "filter_backup.cpp does not compile and link against the installed library: " + built.stderr


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}."
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."


def test_adversarial_corpus():
    clean_files = glob.glob("/app/corpora/clean/*.json")
    evil_files = glob.glob("/app/corpora/evil/*.json")
    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for path in clean_files:
        try:
            if run_filter(EXECUTABLE, path) != 0:
                clean_failures.append(os.path.basename(path))
        except Exception as exc:
            clean_failures.append(f"{os.path.basename(path)} (error: {exc})")

    evil_failures = []
    for path in evil_files:
        try:
            if run_filter(EXECUTABLE, path) != 1:
                evil_failures.append(os.path.basename(path))
        except Exception as exc:
            evil_failures.append(f"{os.path.basename(path)} (error: {exc})")

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures[:5])}{'...' if len(clean_failures) > 5 else ''}")
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures[:5])}{'...' if len(evil_failures) > 5 else ''}")
    assert not clean_failures and not evil_failures, " | ".join(errors)


def test_randomized_unlabelled_backups():
    safe_sets = [
        ["MATCH (n) RETURN n"],
        ["CREATE (n:Node {value: 7})", "MERGE (m:Node {value: 8})"],
        ["MATCH (n) SET n.active = true RETURN n"],
        ["CALL db.labels()"],
    ]
    evil_sets = [
        ["MATCH (n) dElEtE n"],
        ["MATCH (n) RETURN n", "DrOp INDEX item_index"],
        ["MATCH (n) ReMoVe n.secret RETURN n"],
        ["cAlL DbMs.security.createUser('x', 'y', false)"],
    ]

    with tempfile.TemporaryDirectory(prefix="verification_" + secrets.token_hex(6) + "_") as directory:
        cases = []
        for _ in range(5):
            for queries in safe_sets:
                cases.append((list(queries), 0))
            for queries in evil_sets:
                cases.append((list(queries), 1))
        random.SystemRandom().shuffle(cases)

        materialized = []
        for queries, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump({"queries": queries}, handle)
            materialized.append((path, expected))

        for executable in (EXECUTABLE, REBUILT):
            for path, expected in materialized:
                assert run_filter(executable, path) == expected, f"Wrong result for generated backup {os.path.basename(path)}"


def test_program_uses_extracted_queries():
    query_key = "Q_" + secrets.token_hex(12)
    log_key = "L_" + secrets.token_hex(12)
    preload_source = "/tmp/preload_" + secrets.token_hex(8) + ".cpp"
    preload_library = preload_source[:-4] + ".so"
    log_path = "/tmp/calls_" + secrets.token_hex(8)

    code = f'''#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>
std::vector<std::string> extract_queries(const std::string& filepath) {{
    const char* log = std::getenv("{log_key}");
    if (log) {{ std::ofstream out(log, std::ios::app); out << filepath << "\\n"; }}
    const char* query = std::getenv("{query_key}");
    return query ? std::vector<std::string>{{std::string(query)}} : std::vector<std::string>{{}};
}}
'''
    with open(preload_source, "w", encoding="utf-8") as handle:
        handle.write(code)
    built = subprocess.run(["g++", "-std=c++17", "-shared", "-fPIC", preload_source, "-o", preload_library], capture_output=True, text=True)
    assert built.returncode == 0, built.stderr

    with tempfile.TemporaryDirectory(prefix="input_" + secrets.token_hex(6) + "_") as directory:
        actual_evil = os.path.join(directory, secrets.token_hex(10) + ".json")
        actual_safe = os.path.join(directory, secrets.token_hex(10) + ".json")
        with open(actual_evil, "w", encoding="utf-8") as handle:
            json.dump({"queries": ["DROP INDEX hidden"]}, handle)
        with open(actual_safe, "w", encoding="utf-8") as handle:
            json.dump({"queries": ["MATCH (n) RETURN n"]}, handle)

        common = {"LD_PRELOAD": preload_library, log_key: log_path}
        assert run_filter(EXECUTABLE, actual_evil, {**common, query_key: "MATCH (n) RETURN n"}) == 0
        assert run_filter(EXECUTABLE, actual_safe, {**common, query_key: "mAtCh (n) DeLeTe n"}) == 1

    with open(log_path, encoding="utf-8") as handle:
        calls = [line.strip() for line in handle if line.strip()]
    assert len(calls) >= 2, "extract_queries was not called for each tested backup."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
