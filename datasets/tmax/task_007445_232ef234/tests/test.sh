#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
import secrets
import subprocess
import sys
import unittest

PROJECT_DIR = "/home/user/project"
LIB_PATH = os.path.join(PROJECT_DIR, "build", "libprocessor.so")


def run(command, **kwargs):
    return subprocess.run(command, **kwargs)


def test_file_organization():
    """Check that directories are created and files are moved properly."""
    src_dir = os.path.join(PROJECT_DIR, "src")
    tests_dir = os.path.join(PROJECT_DIR, "tests")
    build_dir = os.path.join(PROJECT_DIR, "build")

    assert os.path.isdir(src_dir), f"{src_dir} directory is missing."
    assert os.path.isdir(tests_dir), f"{tests_dir} directory is missing."
    assert os.path.isdir(build_dir), f"{build_dir} directory is missing."

    assert os.path.isfile(os.path.join(src_dir, "processor.c")), "processor.c is not in src/"
    assert os.path.isfile(os.path.join(src_dir, "processor.h")), "processor.h is not in src/"
    assert os.path.isfile(os.path.join(tests_dir, "test_processor.py")), "test_processor.py is not in tests/"

    assert not os.path.exists(os.path.join(PROJECT_DIR, "processor.c")), "processor.c was not moved from root."
    assert not os.path.exists(os.path.join(PROJECT_DIR, "processor.h")), "processor.h was not moved from root."
    assert not os.path.exists(os.path.join(PROJECT_DIR, "test_processor.py")), "test_processor.py was not moved from root."


def test_makefile_and_build():
    """Exercise clean and make, then validate the produced shared object."""
    makefile_path = os.path.join(PROJECT_DIR, "Makefile")
    assert os.path.isfile(makefile_path), "Makefile is missing."

    marker = os.path.join(PROJECT_DIR, "build", ".clean-check-" + secrets.token_hex(8))
    with open(marker, "w", encoding="utf-8") as f:
        f.write("remove me")

    clean = run(["make", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stderr}\n{clean.stdout}"
    assert not os.path.exists(marker), "clean target did not remove build directory contents"
    build_dir = os.path.join(PROJECT_DIR, "build")
    if os.path.isdir(build_dir):
        assert not os.listdir(build_dir), "clean target left files in build/"

    dry = run(["make", "-B", "-n"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert dry.returncode == 0, f"make dry run failed:\n{dry.stderr}\n{dry.stdout}"
    commands = dry.stdout + "\n" + dry.stderr
    assert "-fPIC" in commands, "build command does not include -fPIC"
    assert "-shared" in commands, "build command does not include -shared"

    result = run(["make"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}"
    assert os.path.getsize(LIB_PATH) > 0, "Shared library is empty"

    elf = run(["readelf", "-h", LIB_PATH], capture_output=True, text=True)
    assert elf.returncode == 0, f"libprocessor.so is not a valid ELF file:\n{elf.stderr}"
    assert "DYN (Shared object file)" in elf.stdout, "libprocessor.so is not an ELF shared object"

    symbols = run(["nm", "-D", "--defined-only", LIB_PATH], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Could not inspect shared-library symbols:\n{symbols.stderr}"
    assert any(line.split()[-1:] == ["process_data"] for line in symbols.stdout.splitlines()), \
        "libprocessor.so does not export process_data"


def test_memory_leak_fixed():
    """Retain the source check and exercise the implementation under Valgrind."""
    processor_c_path = os.path.join(PROJECT_DIR, "src", "processor.c")
    assert os.path.isfile(processor_c_path), f"{processor_c_path} not found."
    with open(processor_c_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "free(" in content, "Memory leak not fixed: free() is missing in processor.c"

    values = [secrets.randbelow(200001) - 100000 for _ in range(80)]
    harness = "/tmp/check_processor_behavior.py"
    with open(harness, "w", encoding="utf-8") as f:
        f.write('''import ctypes, sys\nlib = ctypes.CDLL(sys.argv[1])\nlib.process_data.argtypes = [ctypes.c_int]\nlib.process_data.restype = ctypes.c_int\nfor raw in sys.argv[2:]:\n    value = int(raw)\n    actual = lib.process_data(value)\n    if actual != value + 50:\n        raise SystemExit("process_data(%d) returned %d, expected %d" % (value, actual, value + 50))\n''')

    command = [
        "valgrind", "--leak-check=full", "--error-exitcode=1",
        sys.executable, harness, LIB_PATH, *map(str, values)
    ]
    checked = run(command, cwd=PROJECT_DIR, capture_output=True, text=True)
    output = checked.stdout + "\n" + checked.stderr
    assert checked.returncode == 0, f"Independent behavior/Valgrind check failed:\n{output}"
    assert "definitely lost: 0 bytes in 0 blocks" in output, \
        f"Independent Valgrind run found a leak or did not complete:\n{output}"


def test_fixture_loads_real_library():
    """Require TestProcessor.setUp to load the built library as a real ctypes library."""
    test_path = os.path.join(PROJECT_DIR, "tests", "test_processor.py")
    spec = importlib.util.spec_from_file_location("submitted_test_processor", test_path)
    assert spec is not None and spec.loader is not None, "Could not import tests/test_processor.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    cls = getattr(module, "TestProcessor", None)
    assert isinstance(cls, type) and issubclass(cls, unittest.TestCase), "TestProcessor unittest class is missing"
    assert "setUp" in cls.__dict__, "TestProcessor does not define setUp"
    assert "test_process" in cls.__dict__, "TestProcessor.test_process is missing"

    case = cls("test_process")
    case.setUp()
    try:
        loaded = getattr(case, "lib", None)
        assert isinstance(loaded, ctypes.CDLL), "setUp did not assign a ctypes-loaded library to self.lib"
        loaded_name = os.fspath(loaded._name)
        if not os.path.isabs(loaded_name):
            loaded_name = os.path.join(PROJECT_DIR, loaded_name)
        assert os.path.realpath(loaded_name) == os.path.realpath(LIB_PATH), \
            f"setUp loaded {loaded._name!r}, not ../build/libprocessor.so"
        loaded.process_data.argtypes = [ctypes.c_int]
        loaded.process_data.restype = ctypes.c_int
        probe = secrets.randbelow(10000) - 5000
        assert loaded.process_data(probe) == probe + 50
    finally:
        if hasattr(case, "tearDown"):
            case.tearDown()


def test_python_tests_pass():
    """Run the submitted Python test suite and check if it passes."""
    result = run(
        ["python3", "-m", "unittest", "discover", "-s", "tests"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Python tests failed:\n{result.stderr}\n{result.stdout}"
    combined = result.stdout + "\n" + result.stderr
    assert "Ran 0 tests" not in combined, "The submitted test suite contains no discoverable tests"


def test_valgrind_report():
    """Validate the submitted report, then regenerate it with the required command."""
    report_path = os.path.join(PROJECT_DIR, "valgrind_report.txt")
    assert os.path.isfile(report_path), f"Valgrind report not found at {report_path}"
    with open(report_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    assert "definitely lost: 0 bytes in 0 blocks" in content, (
        "Valgrind report does not show 0 bytes definitely lost. "
        f"Report content:\n{content}"
    )

    with open(report_path, "w", encoding="utf-8") as report:
        result = run(
            ["valgrind", "--leak-check=full", "--error-exitcode=1",
             "python3", "-m", "unittest", "discover", "-s", "tests"],
            cwd=PROJECT_DIR,
            stdout=report,
            stderr=subprocess.STDOUT,
            text=True
        )
    with open(report_path, "r", encoding="utf-8", errors="replace") as f:
        regenerated = f.read()
    assert result.returncode == 0, f"Required Valgrind command failed:\n{regenerated}"
    assert "valgrind" in regenerated.lower(), "Report was not produced by Valgrind"
    assert "definitely lost: 0 bytes in 0 blocks" in regenerated, \
        f"Regenerated report does not show zero definitely-lost bytes:\n{regenerated}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
