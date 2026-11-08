#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

ROOT = "/home/user/build_router"
ROUTER = os.path.join(ROOT, "router")


def run_command(args, timeout=15, cwd=ROOT):
    try:
        return subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {args}")


def assert_elf_executable():
    assert os.path.isfile(ROUTER), f"Executable {ROUTER} is missing."
    assert os.access(ROUTER, os.X_OK), f"{ROUTER} is not executable."
    with open(ROUTER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "router is not a compiled ELF executable."


def router_output(*args, timeout=5):
    result = run_command([ROUTER, *args], timeout=timeout)
    assert result.returncode == 0, (
        f"router {' '.join(args)} exited with {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    return result.stdout.strip().splitlines()


def expected_comparison(v1, v2):
    a = tuple(int(part) for part in v1.split("."))
    b = tuple(int(part) for part in v2.split("."))
    return 1 if a > b else -1 if a < b else 0


def test_version_tests_log():
    log_path = "/home/user/version_tests.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()

    content = [line.strip() for line in content if line.strip()]
    expected = [
        "[CROSS COMPILE MODE ENABLED]",
        "1",
        "[CROSS COMPILE MODE ENABLED]",
        "0",
        "[CROSS COMPILE MODE ENABLED]",
        "-1"
    ]
    assert content == expected, f"Contents of {log_path} do not match the expected output. Got: {content}"


def test_benchmark_results_log():
    log_path = "/home/user/benchmark_results.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert "Benchmark completed: 5000 requests processed." in content, f"{log_path} does not contain the expected benchmark completion message."


def test_makefile_cross_compile_mode():
    makefile_path = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(makefile_path), f"File {makefile_path} is missing."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "CROSS_COMPILE_MODE" in content, "Makefile does not contain 'CROSS_COMPILE_MODE' as required for the ARCH=cross conditional."


def test_url_parser_segfault_fixed():
    assert os.path.isfile(ROUTER), f"Executable {ROUTER} is missing. Did you compile the project?"
    assert os.access(ROUTER, os.X_OK), f"{ROUTER} is not executable."

    try:
        result = subprocess.run(
            [ROUTER, "parse", "build://project/1.2.3"],
            capture_output=True,
            text=True,
            timeout=2
        )
        assert result.returncode == 0, f"Router exited with code {result.returncode} when parsing a URL without '?arch='. It might still be segfaulting."
        assert "ARCH: NONE" in result.stdout, "Router did not print 'ARCH: NONE' for a URL missing the architecture parameter."
    except subprocess.TimeoutExpired:
        pytest.fail("Router timed out when parsing a URL without '?arch='.")


def test_clean_builds_and_runtime_behavior():
    # A clean normal build must resolve the original object/linking problem.
    clean = run_command(["make", "clean"])
    assert clean.returncode == 0, f"make clean failed: {clean.stdout}\n{clean.stderr}"
    normal = run_command(["make"], timeout=30)
    assert normal.returncode == 0, f"Normal clean build failed: {normal.stdout}\n{normal.stderr}"
    assert_elf_executable()

    # Normal builds must not enable the conditional cross-compilation macro.
    assert router_output("semver", "1.10.0", "1.2.0") == ["1"]

    # Exercise URL parsing independently of the submitted logs and benchmark message.
    valid_urls = [
        ("build://project/1.2.3?arch=arm64", "arm64"),
        ("build://other/9.8.7?arch=x86_64", "x86_64"),
        ("build://p/0.0.1?arch=riscv64", "riscv64"),
    ]
    for url, arch in valid_urls:
        assert router_output("parse", url) == [f"ARCH: {arch}"]

    malformed_urls = [
        "build://project/1.2.3",
        "build://project/1.2.3?foo=arm64",
        "build://project/1.2.3?",
        "not-a-build-url",
    ]
    for url in malformed_urls:
        assert router_output("parse", url) == ["ARCH: NONE"]

    # Derive expected semantic-version answers rather than trusting a fixed log.
    pairs = [
        ("1.10.0", "1.2.0"),
        ("2.0.0", "2.0.0"),
        ("0.9.5", "0.10.1"),
        ("10.0.1", "9.999.999"),
        ("3.12.4", "3.12.40"),
        ("100.2.3", "100.2.2"),
    ]
    rng = random.Random(94721)
    for _ in range(50):
        left = tuple(rng.randint(0, 10000) for _ in range(3))
        right = tuple(rng.randint(0, 10000) for _ in range(3))
        pairs.append((".".join(map(str, left)), ".".join(map(str, right))))

    for v1, v2 in pairs:
        expected = str(expected_comparison(v1, v2))
        assert router_output("semver", v1, v2) == [expected], f"Incorrect comparison for {v1} and {v2}"
        inverse = str(expected_comparison(v2, v1))
        assert router_output("semver", v2, v1) == [inverse], f"Incorrect reverse comparison for {v2} and {v1}"

    # Rebuild from clean with ARCH=cross and prove the macro affects the binary.
    clean = run_command(["make", "clean"])
    assert clean.returncode == 0, f"make clean before cross build failed: {clean.stdout}\n{clean.stderr}"
    cross = run_command(["make", "ARCH=cross"], timeout=30)
    assert cross.returncode == 0, f"Cross-mode clean build failed: {cross.stdout}\n{cross.stderr}"
    assert_elf_executable()

    assert router_output("semver", "21.100.7", "21.99.999") == [
        "[CROSS COMPILE MODE ENABLED]", "1"
    ]
    assert router_output("parse", "build://project/4.5.6?arch=ppc64le") == [
        "[CROSS COMPILE MODE ENABLED]", "ARCH: ppc64le"
    ]
    assert router_output("parse", "build://project/4.5.6") == [
        "[CROSS COMPILE MODE ENABLED]", "ARCH: NONE"
    ]

    # Actually execute the supplied benchmark against the rebuilt router.
    benchmark = run_command(["bash", os.path.join(ROOT, "benchmark.sh")], timeout=60)
    assert benchmark.returncode == 0, f"Benchmark failed: {benchmark.stdout}\n{benchmark.stderr}"
    assert benchmark.stdout.strip() == "Benchmark completed: 5000 requests processed.", (
        f"Unexpected benchmark output: {benchmark.stdout!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
