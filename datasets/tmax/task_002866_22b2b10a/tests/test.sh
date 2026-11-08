#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import uuid

import pytest

EXECUTABLE = "/home/user/classifier"
SOURCE = "/home/user/classifier.cpp"
PROJECT = "/app/simple-elf-validator-0.1.0"
LIBRARY = os.path.join(PROJECT, "libelfval.a")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def test_makefile_fixed_and_library_valid():
    makefile = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(makefile), f"Makefile {makefile} is missing."

    dry_run = run(["make", "-B", "-n"], cwd=PROJECT)
    assert dry_run.returncode == 0, dry_run.stdout + dry_run.stderr
    compile_lines = dry_run.stdout + dry_run.stderr
    assert re.search(r"(^|[\s/])(g\+\+|c\+\+)(\s|$)", compile_lines, re.MULTILINE), \
        "The Makefile must compile the C++ source with a C++ compiler driver."

    cleaned = run(["make", "clean"], cwd=PROJECT)
    assert cleaned.returncode == 0, cleaned.stdout + cleaned.stderr
    built = run(["make"], cwd=PROJECT)
    assert built.returncode == 0, built.stdout + built.stderr

    assert os.path.isfile(LIBRARY), f"Static library {LIBRARY} does not exist. Did you fix the Makefile and run make?"
    listing = run(["ar", "t", LIBRARY])
    assert listing.returncode == 0 and listing.stdout.strip(), "libelfval.a is not a valid non-empty archive."

    symbols = run(["nm", "-C", LIBRARY])
    assert symbols.returncode == 0, symbols.stderr
    assert re.search(r"\b[Tt]\s+is_valid_elf\(char const\*\)", symbols.stdout), \
        "libelfval.a does not define is_valid_elf(const char*)."

    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "probe.cpp")
        binary = os.path.join(td, "probe")
        with open(probe, "w") as f:
            f.write('#include "elf_validator.h"\nint main(int argc, char** argv) { return argc == 2 && is_valid_elf(argv[1]) ? 0 : 1; }\n')
        linked = run(["g++", "-I", PROJECT, probe, LIBRARY, "-o", binary])
        assert linked.returncode == 0, "libelfval.a cannot be linked into a C++ program:\n" + linked.stderr


def test_classifier_executable_exists_and_uses_library():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile your tool?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."

    symbols = run(["nm", EXECUTABLE])
    assert symbols.returncode == 0, "classifier must retain the linked validator symbol."
    assert re.search(r"\b[Tt]\s+_Z12is_valid_elfPKc\b", symbols.stdout), \
        "classifier does not contain the is_valid_elf implementation from the static library."

    disassembly = run(["objdump", "-d", EXECUTABLE])
    assert disassembly.returncode == 0, disassembly.stderr
    assert re.search(r"\b(callq?|jmpq?)\b[^\n]*<_Z12is_valid_elfPKc>", disassembly.stdout), \
        "classifier contains is_valid_elf but does not call it."


def test_submitted_source_uses_validator_result():
    with tempfile.TemporaryDirectory() as td:
        true_path = os.path.join(td, "input_" + uuid.uuid4().hex)
        false_path = os.path.join(td, "input_" + uuid.uuid4().hex)
        open(true_path, "wb").write(b"not an elf")
        open(false_path, "wb").write(b"\x7fELFdecoy")

        stub_cpp = os.path.join(td, "stub.cpp")
        stub_obj = os.path.join(td, "stub.o")
        stub_lib = os.path.join(td, "libelfval.a")
        rebuilt = os.path.join(td, "classifier")
        with open(stub_cpp, "w") as f:
            f.write('#include <cstring>\nextern bool is_valid_elf(const char* p) { return std::strcmp(p, ' + json.dumps(true_path) + ') == 0; }\n')

        result = run(["g++", "-c", stub_cpp, "-o", stub_obj])
        assert result.returncode == 0, result.stderr
        result = run(["ar", "rcs", stub_lib, stub_obj])
        assert result.returncode == 0, result.stderr
        result = run(["g++", "-I", PROJECT, SOURCE, stub_lib, "-o", rebuilt])
        assert result.returncode == 0, "classifier.cpp must compile and link against libelfval.a:\n" + result.stderr

        assert run([rebuilt, true_path]).returncode == 0, \
            "classifier.cpp does not use a true result from is_valid_elf."
        assert run([rebuilt, false_path]).returncode == 1, \
            "classifier.cpp does not use a false result from is_valid_elf."


def test_randomized_content_classifier():
    cases = [
        (b"\x7fELF", 0),
        (b"\x7fELF" + os.urandom(257), 0),
        (b"", 1),
        (b"\x7f", 1),
        (b"\x7fEL", 1),
        (b"ELF\x7f" + os.urandom(30), 1),
        (b"\x7fELX" + os.urandom(30), 1),
        (os.urandom(128), 1),
    ]

    with tempfile.TemporaryDirectory(prefix="elf-check-" + uuid.uuid4().hex + "-") as td:
        rebuilt = os.path.join(td, "rebuilt-classifier")
        result = run(["g++", "-I", PROJECT, SOURCE, LIBRARY, "-o", rebuilt])
        assert result.returncode == 0, "Could not rebuild classifier.cpp against libelfval.a:\n" + result.stderr

        for index, (content, expected) in enumerate(cases):
            misleading = "evil" if expected == 0 else "clean"
            path = os.path.join(td, f"{misleading}_{uuid.uuid4().hex}_{index}")
            with open(path, "wb") as f:
                f.write(content)
            for binary in (EXECUTABLE, rebuilt):
                result = run([binary, path])
                assert result.returncode == expected, \
                    f"{binary} returned {result.returncode} for generated case {index}; expected {expected}."


def test_adversarial_corpus():
    clean_dir = "/app/hidden_corpus/clean"
    evil_dir = "/app/hidden_corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus dir {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus dir {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    failed_clean = []
    failed_evil = []
    for path in clean_files:
        if run([EXECUTABLE, path]).returncode != 0:
            failed_clean.append(os.path.basename(path))
    for path in evil_files:
        if run([EXECUTABLE, path]).returncode != 1:
            failed_evil.append(os.path.basename(path))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files rejected. Offending files: {', '.join(failed_clean[:10])}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed. Offending files: {', '.join(failed_evil[:10])}")
    assert not failed_clean and not failed_evil, " | ".join(errors)


def test_libelfval_built():
    assert os.path.isfile(LIBRARY), f"Static library {LIBRARY} does not exist. Did you fix the Makefile and run make?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
