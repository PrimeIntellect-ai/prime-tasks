#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

PROJECT_DIR = pathlib.Path("/home/user/project")
EXPECTED_OUTPUT = "SUCCESS: Linked version 2.0.5"

EXPECTED_SOURCES = {
    "lib-1.5.2/mathalg.cpp": 'extern "C" const char* get_version() { return "1.5.2"; }\nextern "C" int compute(int a, int b) { return a + b; }\n',
    "lib-1.11.0/mathalg.cpp": 'extern "C" const char* get_version() { return "1.11.0"; }\nextern "C" int compute(int a, int b) { return a + b; }\n',
    "lib-2.0.5/mathalg.cpp": 'extern "C" const char* get_version() { return "2.0.5"; }\nextern "C" int compute(int a, int b) { return a + b; }\n',
    "test_suite.cpp": '''#include <iostream>
#include <string>

extern "C" const char* get_version();
extern "C" int compute(int a, int b);

int main() {
    std::string ver = get_version();
    int major = ver[0] - '0';
    if (major < 2) {
        std::cerr << "Test failed: library version " << ver << " is less than 2.0.0" << std::endl;
        return 1;
    }
    if (compute(3, 4) != 7) {
        std::cerr << "Test failed: compute error" << std::endl;
        return 1;
    }
    std::cout << "SUCCESS: Linked version " << ver << std::endl;
    return 0;
}
''',
}


def run(cmd, cwd, timeout=15):
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        env={"PATH": "/usr/bin:/bin"},
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def readelf(path, option):
    result = run(["/usr/bin/readelf", option, str(path)], path.parent)
    assert result.returncode == 0, f"readelf failed for {path}:\n{result.stderr}"
    return result.stdout


def assert_real_shared_library(path, expected_version):
    assert path.is_file(), f"Shared library {path} is missing. Did the Makefile build it?"
    assert path.read_bytes()[:4] == b"\x7fELF", f"{path} is not an ELF shared object"
    header = readelf(path, "-h")
    assert re.search(r"Type:\s+DYN\b", header), f"{path} is not an ELF shared object"

    try:
        library = ctypes.CDLL(str(path))
        library.get_version.restype = ctypes.c_char_p
        library.compute.argtypes = [ctypes.c_int, ctypes.c_int]
        library.compute.restype = ctypes.c_int
        version = library.get_version().decode("ascii")
    except Exception as exc:
        pytest.fail(f"Could not load or call {path} as a shared library: {exc}")

    assert version == expected_version, (
        f"Shared library reports version {version!r}, expected {expected_version!r}"
    )
    for a, b in [(-17, 9), (0, 0), (123, 456)]:
        assert library.compute(a, b) == a + b, (
            f"compute({a}, {b}) from {path} returned the wrong result"
        )


def assert_real_linked_executable(exe_path, library_path):
    assert exe_path.is_file(), f"Executable {exe_path} is missing. Did the Makefile build it?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    assert exe_path.read_bytes()[:4] == b"\x7fELF", f"{exe_path} is not an ELF executable"

    dynamic = readelf(exe_path, "-d")
    assert re.search(r"\(NEEDED\).*\[libmathalg\.so\]", dynamic), (
        "test_suite does not have a dynamic dependency on libmathalg.so"
    )
    rpath_match = re.search(r"\((?:RPATH|RUNPATH)\).*\[(.*?)\]", dynamic)
    assert rpath_match, "test_suite has no RPATH or RUNPATH"
    entries = rpath_match.group(1).split(":")
    allowed = {"$ORIGIN", "${ORIGIN}", ".", str(exe_path.parent)}
    assert any(entry in allowed for entry in entries), (
        f"RPATH/RUNPATH does not search the executable/current directory: {entries}"
    )

    linked = run(["/usr/bin/ldd", str(exe_path)], exe_path.parent)
    assert linked.returncode == 0, f"ldd failed for {exe_path}:\n{linked.stderr}"
    match = re.search(r"^\s*libmathalg\.so\s+=>\s+(\S+)", linked.stdout, re.MULTILINE)
    assert match and match.group(1) != "not", (
        f"libmathalg.so was not resolved by the executable:\n{linked.stdout}"
    )
    assert pathlib.Path(match.group(1)).resolve() == library_path.resolve(), (
        f"test_suite resolves libmathalg.so to {match.group(1)}, not {library_path}"
    )


def test_original_sources_were_not_modified():
    for relative, expected in EXPECTED_SOURCES.items():
        path = PROJECT_DIR / relative
        assert path.is_file(), f"Required source file {path} is missing"
        assert path.read_text() == expected, f"Instruction forbids modifying {path}"


def test_result_log_correct():
    """Verify that the test_result.log exists and contains the correct output."""
    log_path = PROJECT_DIR / "test_result.log"
    assert log_path.is_file(), f"The file {log_path} does not exist. Did you run the executable and redirect output?"
    content = log_path.read_text().strip()
    assert content == EXPECTED_OUTPUT, f"Expected log content '{EXPECTED_OUTPUT}', but got '{content}'"


def test_shared_library_built():
    """Verify that the shared library was built and is functional."""
    assert_real_shared_library(PROJECT_DIR / "libmathalg.so", "2.0.5")


def test_executable_built():
    """Verify that test_suite is a real executable linked to the local shared library."""
    assert_real_linked_executable(
        PROJECT_DIR / "test_suite", PROJECT_DIR / "libmathalg.so"
    )


def test_executable_runs_independently():
    """Verify that the executable runs successfully without LD_LIBRARY_PATH."""
    exe_path = PROJECT_DIR / "test_suite"
    assert exe_path.is_file(), "test_suite executable not found."
    try:
        result = run(["./test_suite"], PROJECT_DIR, timeout=5)
    except Exception as exc:
        pytest.fail(f"Failed to execute ./test_suite: {exc}")

    assert result.returncode == 0, (
        f"test_suite failed to run independently. Return code: {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}\n"
        "Did you correctly set the rpath during linking?"
    )
    assert EXPECTED_OUTPUT in result.stdout, (
        f"test_suite output was incorrect when run independently.\nOutput: {result.stdout}"
    )


def test_makefile_dynamically_selects_highest_semantic_version():
    """Rebuild in isolation with a newly introduced highest semantic version."""
    with tempfile.TemporaryDirectory(prefix="makefile-semver-") as temp_name:
        temp = pathlib.Path(temp_name)
        shutil.copy2(PROJECT_DIR / "Makefile", temp / "Makefile")
        shutil.copy2(PROJECT_DIR / "test_suite.cpp", temp / "test_suite.cpp")
        for directory in PROJECT_DIR.glob("lib-*"):
            if directory.is_dir():
                shutil.copytree(directory, temp / directory.name)

        version = f"{secrets.choice([7, 8, 9])}.{secrets.randbelow(800) + 100}.{secrets.randbelow(800) + 100}"
        new_library_dir = temp / f"lib-{version}"
        new_library_dir.mkdir()
        (new_library_dir / "mathalg.cpp").write_text(
            f'extern "C" const char* get_version() {{ return "{version}"; }}\n'
            'extern "C" int compute(int a, int b) { return a + b; }\n'
        )

        built = run(["/usr/bin/make"], temp, timeout=30)
        assert built.returncode == 0, (
            f"Makefile failed when rebuilding with a new highest version:\n"
            f"stdout:\n{built.stdout}\nstderr:\n{built.stderr}"
        )

        library = temp / "libmathalg.so"
        executable = temp / "test_suite"
        assert_real_shared_library(library, version)
        assert_real_linked_executable(executable, library)

        result = run(["./test_suite"], temp, timeout=5)
        expected = f"SUCCESS: Linked version {version}"
        assert result.returncode == 0, (
            f"Rebuilt executable failed without LD_LIBRARY_PATH:\n{result.stderr}"
        )
        assert result.stdout.strip() == expected, (
            f"Rebuilt executable used the wrong version: {result.stdout!r}, expected {expected!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
