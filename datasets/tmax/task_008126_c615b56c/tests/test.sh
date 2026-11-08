#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/project"
SCRIPT_PATH = os.path.join(PROJECT_DIR, "build_and_run.sh")
BINARY_PATH = os.path.join(PROJECT_DIR, "math_runner")
LIB_PATH = os.path.join(PROJECT_DIR, "libalgo.so")


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def run_runner(limit, timeout=5):
    return subprocess.run(
        [BINARY_PATH, f"math://service/compute?limit={limit}"],
        cwd=PROJECT_DIR,
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def assert_exact_result(stdout, limit, expected):
    pattern = rf"^\s*limit:\s*{limit}\s+result:\s*{expected}\s*$"
    assert re.fullmatch(pattern, stdout), (
        f"Unexpected output for limit={limit}: {stdout!r}; "
        f"expected protobuf output containing exactly limit={limit}, result={expected}."
    )


def test_build_script_exists_and_executable():
    script_path = os.path.join(PROJECT_DIR, "build_and_run.sh")
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_build_script_rebuilds_every_required_artifact():
    # Force the submitted orchestrator to do the generation and build rather than
    # accepting artifacts fabricated before verification.
    for name in (
        "math_service.pb.cc",
        "math_service.pb.h",
        "libalgo.so",
        "math_runner",
        "output.log",
    ):
        path = os.path.join(PROJECT_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["./build_and_run.sh"],
        cwd=PROJECT_DIR,
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"build_and_run.sh failed. stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    for name in ("math_service.pb.cc", "math_service.pb.h"):
        path = os.path.join(PROJECT_DIR, name)
        assert os.path.isfile(path), f"Generated protobuf binding {path} is missing."
        assert os.path.getsize(path) > 0, f"Generated protobuf binding {path} is empty."


def test_libalgo_exists():
    lib_path = os.path.join(PROJECT_DIR, "libalgo.so")
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not built or is missing."


def test_math_runner_exists():
    binary_path = os.path.join(PROJECT_DIR, "math_runner")
    assert os.path.isfile(binary_path), f"Executable {binary_path} was not built or is missing."

    st = os.stat(binary_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Executable {binary_path} does not have execute permissions."


def test_math_runner_rpath():
    binary_path = os.path.join(PROJECT_DIR, "math_runner")
    assert os.path.isfile(binary_path), "Cannot check rpath because math_runner is missing."

    result = subprocess.run(["readelf", "-d", binary_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run readelf on {binary_path}."

    rpath_found = False
    for line in result.stdout.splitlines():
        if "RPATH" in line or "RUNPATH" in line:
            # Check if the rpath points to the current directory, project directory, or uses $ORIGIN
            if "." in line or PROJECT_DIR in line or "$ORIGIN" in line:
                rpath_found = True
                break

    assert rpath_found, f"{binary_path} does not have a valid RPATH/RUNPATH set to find libalgo.so."


def test_math_runner_really_links_required_libraries_and_symbol():
    dynamic = subprocess.run(
        ["readelf", "-d", BINARY_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"\(NEEDED\).*\[libalgo\.so\]", dynamic), (
        "math_runner does not have libalgo.so as a dynamic dependency."
    )
    assert re.search(r"\(NEEDED\).*\[libprotobuf\.so", dynamic), (
        "math_runner does not have the protobuf runtime as a dynamic dependency."
    )

    runner_symbols = subprocess.run(
        ["nm", "-D", BINARY_PATH], capture_output=True, text=True, check=True
    ).stdout
    library_symbols = subprocess.run(
        ["nm", "-D", LIB_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert any(" U " in line and "compute_sum" in line for line in runner_symbols.splitlines()), (
        "math_runner does not dynamically reference compute_sum."
    )
    assert any(
        re.search(r"\s[TW]\s+.*compute_sum", line)
        for line in library_symbols.splitlines()
    ), "libalgo.so does not export compute_sum."


def test_output_log_correct():
    log_path = os.path.join(PROJECT_DIR, "output.log")
    assert os.path.isfile(log_path), f"Output log {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    # The sum of 1 to 15 is 120. Protobuf ShortDebugString format typically looks like "limit: 15 result: 120"
    assert "limit: 15" in content, f"output.log does not contain 'limit: 15'. Content: {content}"
    assert "result: 120" in content, f"output.log does not contain 'result: 120'. Content: {content}"


def test_math_runner_execution_without_ld_library_path():
    binary_path = os.path.join(PROJECT_DIR, "math_runner")
    assert os.path.isfile(binary_path), "Cannot test execution because math_runner is missing."

    # Run the binary from the project directory without setting LD_LIBRARY_PATH
    # to ensure rpath is actually working.
    env = os.environ.copy()
    if "LD_LIBRARY_PATH" in env:
        del env["LD_LIBRARY_PATH"]

    try:
        result = subprocess.run(
            [binary_path, "math://service/compute?limit=5"],
            cwd=PROJECT_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=5
        )
        assert result.returncode == 0, f"math_runner failed to execute. Error: {result.stderr}"
        assert "limit: 5" in result.stdout and "result: 15" in result.stdout, "math_runner did not produce expected output for limit=5."
    except Exception as e:
        pytest.fail(f"Execution of math_runner failed: {e}")


def test_math_runner_on_unpredictable_limits():
    # Values are selected only after the agent has finished, preventing a fixed-output
    # executable from satisfying the behavioral test.
    limits = {secrets.randbelow(5000) + 1 for _ in range(8)}
    while len(limits) < 6:
        limits.add(secrets.randbelow(5000) + 1)

    for limit in limits:
        result = run_runner(limit)
        assert result.returncode == 0, (
            f"math_runner failed for limit={limit}: {result.stderr}"
        )
        assert_exact_result(result.stdout, limit, limit * (limit + 1) // 2)


def test_math_runner_uses_compute_sum_from_libalgo():
    # Temporarily substitute a compatible library whose result is deliberately not
    # an arithmetic sum. The executable must report that result, proving that its
    # output is obtained through the dynamically linked compute_sum implementation.
    backup = LIB_PATH + ".verifier-backup"
    assert not os.path.exists(backup), f"Unexpected verifier backup already exists: {backup}"

    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, "probe.cc")
        probe = os.path.join(tmp, "libalgo.so")
        with open(source, "w") as f:
            f.write("int compute_sum(int limit) { return limit * 37 + 11; }\n")
        compiled = subprocess.run(
            ["g++", "-shared", "-fPIC", source, "-o", probe],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"Could not build verifier probe library: {compiled.stderr}"

        os.replace(LIB_PATH, backup)
        try:
            os.replace(probe, LIB_PATH)
            limit = secrets.randbelow(1000) + 20
            result = run_runner(limit)
            assert result.returncode == 0, (
                f"math_runner failed with a compatible replacement libalgo.so: {result.stderr}"
            )
            assert_exact_result(result.stdout, limit, limit * 37 + 11)
        finally:
            if os.path.exists(LIB_PATH):
                os.remove(LIB_PATH)
            os.replace(backup, LIB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
