#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

BASE_DIR = Path("/home/user/test_env")


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", BASE_DIR)
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 30)
    return subprocess.run(cmd, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def clean_rebuild():
    # A valid Makefile must create both output directories and artifacts from scratch.
    shutil.rmtree(BASE_DIR / "lib", ignore_errors=True)
    shutil.rmtree(BASE_DIR / "bin", ignore_errors=True)
    proc = run(["make"])
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}\n{proc.stderr}"


def test_protected_inputs_unchanged():
    assert (BASE_DIR / "src/libdata.c").read_text() == '''#include <stdio.h>
#include <stdlib.h>
#include "libdata.h"

int process_data(const char* filename) {
    FILE* f = fopen(filename, "r");
    if (!f) return -1;
    int sum = 0, val;
    while (fscanf(f, "%d", &val) == 1) {
        sum += val;
    }
    fclose(f);
    return sum;
}
'''
    assert (BASE_DIR / "test/runner.cpp").read_text() == '''#include <iostream>
#include "libdata.h"

int main() {
    int result = process_data("data.txt");
    if (result == -1) {
        std::cerr << "Failed to process data." << std::endl;
        return 1;
    }
    std::cout << "Data sum: " << result << std::endl;
    return 0;
}
'''
    assert (BASE_DIR / "data.txt").read_text() == "15\n25\n40\n20\n100\n"


def test_result_log_exists():
    result_path = BASE_DIR / "result.log"
    assert os.path.exists(result_path), f"{result_path} does not exist. The runner output was not saved."
    assert os.path.isfile(result_path), f"{result_path} is not a file."


def test_result_log_content():
    result_path = BASE_DIR / "result.log"
    assert os.path.exists(result_path), "Cannot check content, result.log is missing."
    content = result_path.read_text().strip()

    # Preserve the original assertion for the supplied data.
    expected = "Data sum: 200"
    assert content == expected, f"Expected '{expected}' in result.log, but got '{content}'."

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = run([str(BASE_DIR / "bin/runner")], env=env)
    assert proc.returncode == 0, f"runner failed:\n{proc.stdout}\n{proc.stderr}"
    assert proc.stdout.strip() == content, "result.log does not match the actual runner output."


def test_build_artifacts_exist_and_are_real_binaries():
    lib_path = BASE_DIR / "lib/libdata.so"
    bin_path = BASE_DIR / "bin/runner"

    assert os.path.exists(lib_path), f"Shared library {lib_path} was not built."
    assert os.path.exists(bin_path), f"Executable {bin_path} was not built."
    assert lib_path.is_file(), f"{lib_path} is not a regular file."
    assert bin_path.is_file(), f"{bin_path} is not a regular file."
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."
    assert lib_path.read_bytes()[:4] == b"\x7fELF", f"{lib_path} is not an ELF binary."
    assert bin_path.read_bytes()[:4] == b"\x7fELF", f"{bin_path} is not an ELF binary."

    lib_hdr = run(["readelf", "-h", str(lib_path)])
    runner_hdr = run(["readelf", "-h", str(bin_path)])
    assert lib_hdr.returncode == 0 and re.search(r"Type:\s+DYN", lib_hdr.stdout), "libdata.so is not a shared ELF object."
    assert runner_hdr.returncode == 0 and re.search(r"Type:\s+(?:EXEC|DYN)", runner_hdr.stdout), "runner is not an ELF executable."

    ldd = run(["ldd", str(bin_path)])
    assert ldd.returncode == 0, f"ldd failed:\n{ldd.stdout}\n{ldd.stderr}"
    dependency = next((line for line in ldd.stdout.splitlines() if "libdata.so" in line), "")
    assert dependency, "runner is not dynamically linked against libdata.so."
    assert str(lib_path.resolve()) in dependency, f"runner does not resolve libdata.so from the project lib directory: {dependency}"


def test_abi_fix_in_header_and_linkage():
    header_path = BASE_DIR / "include/libdata.h"
    assert os.path.exists(header_path), f"{header_path} is missing."
    content = header_path.read_text()
    assert 'extern "C"' in content, "The ABI linkage issue was not fixed. Expected 'extern \"C\"' in libdata.h."

    # Compile a fresh C++ caller against the submitted header and C shared library.
    # This fails if extern C only appears in a comment or does not cover process_data.
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        probe = td_path / "probe.cpp"
        probe.write_text('''#include <iostream>
#include "libdata.h"
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::cout << process_data(argv[1]) << "\\n";
    return 0;
}
''')
        probe_bin = td_path / "probe"
        compile_proc = run([
            "g++", str(probe), "-I", str(BASE_DIR / "include"),
            "-L", str(BASE_DIR / "lib"), "-ldata",
            f"-Wl,-rpath,{BASE_DIR / 'lib'}", "-o", str(probe_bin)
        ])
        assert compile_proc.returncode == 0, f"C++ ABI/linkage probe failed:\n{compile_proc.stdout}\n{compile_proc.stderr}"

        values = [317, -42, 8, 1001, -9]
        sample = td_path / "numbers.txt"
        sample.write_text("\n".join(map(str, values)) + "\n")
        probe_proc = run([str(probe_bin), str(sample)])
        assert probe_proc.returncode == 0, f"ABI probe execution failed: {probe_proc.stderr}"
        assert probe_proc.stdout.strip() == str(sum(values)), "libdata.so did not process independently chosen input correctly."


def test_makefile_fpic_fix():
    makefile_path = BASE_DIR / "Makefile"
    assert os.path.exists(makefile_path), f"{makefile_path} is missing."
    content = makefile_path.read_text()
    assert "-fPIC" in content, "The Makefile does not contain '-fPIC' for compiling the shared library."


def test_runner_on_independently_derived_input():
    # runner.cpp reads data.txt relative to its working directory. Use a temporary
    # working directory so a hard-coded output cannot satisfy this check.
    with tempfile.TemporaryDirectory() as td:
        values = [731, -205, 19, 4, -88, 1500]
        Path(td, "data.txt").write_text("\n".join(map(str, values)) + "\n")
        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        proc = run([str(BASE_DIR / "bin/runner")], cwd=td, env=env)
        assert proc.returncode == 0, f"runner failed on test input:\n{proc.stdout}\n{proc.stderr}"
        assert proc.stdout.strip() == f"Data sum: {sum(values)}"
        assert proc.stderr == ""
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
