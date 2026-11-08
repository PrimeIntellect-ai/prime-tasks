#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import string
import subprocess
import tempfile

ROUTER_DIR = "/home/user/router"
ROUTER_PATH = os.path.join(ROUTER_DIR, "router")


def test_00_makefile_link_order_and_clean_build():
    makefile = os.path.join(ROUTER_DIR, "Makefile")
    assert os.path.isfile(makefile), f"{makefile} does not exist."

    clean = subprocess.run(["make", "clean"], cwd=ROUTER_DIR, capture_output=True, text=True, timeout=10)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    dry_run = subprocess.run(["make", "-n"], cwd=ROUTER_DIR, capture_output=True, text=True, timeout=10)
    assert dry_run.returncode == 0, f"make -n failed:\n{dry_run.stdout}\n{dry_run.stderr}"
    link_commands = [line for line in dry_run.stdout.splitlines() if "-o router" in line and "-lm" in line]
    assert link_commands, f"Could not find the router link command with -lm in make output:\n{dry_run.stdout}"
    tokens = shlex.split(link_commands[-1])
    assert "main.o" in tokens and "deeplink_router.o" in tokens, f"Link command does not use the required objects: {link_commands[-1]}"
    assert tokens.index("-lm") > tokens.index("main.o"), f"-lm must follow main.o: {link_commands[-1]}"
    assert tokens.index("-lm") > tokens.index("deeplink_router.o"), f"-lm must follow deeplink_router.o: {link_commands[-1]}"

    build = subprocess.run(["make"], cwd=ROUTER_DIR, capture_output=True, text=True, timeout=20)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(ROUTER_PATH), f"{ROUTER_PATH} does not exist after make."
    with open(ROUTER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not produce a Linux ELF router binary."


def test_router_compiled():
    assert os.path.isfile(ROUTER_PATH), f"{ROUTER_PATH} does not exist. Did you run make?"
    assert os.access(ROUTER_PATH, os.X_OK), f"{ROUTER_PATH} is not executable."


def test_parse_url_independently():
    source = os.path.join(ROUTER_DIR, "deeplink_router.c")
    header = os.path.join(ROUTER_DIR, "deeplink_router.h")
    assert os.path.isfile(source), f"{source} does not exist."
    assert os.path.isfile(header), f"{header} does not exist."

    harness_source = r'''#include <stdio.h>
#include "deeplink_router.h"
int main(int argc, char **argv) {
    ParsedUrl p;
    if (argc != 2) return 2;
    int rc = parse_url(argv[1], &p);
    printf("%d\n%s\n%s\n%s\n%s\n", rc, p.scheme, p.route, p.param_key, p.param_value);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_c = os.path.join(td, "parse_harness.c")
        harness_bin = os.path.join(td, "parse_harness")
        with open(harness_c, "w") as f:
            f.write(harness_source)
        compiled = subprocess.run(
            ["gcc", "-O2", "-I", ROUTER_DIR, harness_c, source, "-o", harness_bin],
            capture_output=True, text=True, timeout=10
        )
        assert compiled.returncode == 0, f"Could not compile deeplink_router.c independently:\n{compiled.stdout}\n{compiled.stderr}"

        cases = [("app", "profile", "id", "123")]
        alphabet = string.ascii_lowercase
        for _ in range(20):
            make_part = lambda n: ''.join(secrets.choice(alphabet) for _ in range(n))
            cases.append((make_part(secrets.randbelow(8) + 1),
                          make_part(secrets.randbelow(18) + 1),
                          make_part(secrets.randbelow(10) + 1),
                          make_part(secrets.randbelow(20) + 1)))

        for scheme, route, key, value in cases:
            url = f"{scheme}://{route}?{key}={value}"
            result = subprocess.run([harness_bin, url], capture_output=True, text=True, timeout=3)
            assert result.returncode == 0, f"Independent parser harness failed for {url!r}: {result.stderr}"
            fields = result.stdout.splitlines()
            assert fields == ["1", scheme, route, key, value], (
                f"parse_url({url!r}) returned {fields!r}; expected "
                f"{['1', scheme, route, key, value]!r}"
            )


def test_router_test_output():
    assert os.path.isfile(ROUTER_PATH), f"{ROUTER_PATH} does not exist."
    try:
        result = subprocess.run([ROUTER_PATH, "test"], capture_output=True, text=True, timeout=5)
    except Exception as e:
        assert False, f"Failed to execute {ROUTER_PATH} test: {e}"
    assert result.returncode == 0, f"Expected exit code 0, got {result.returncode}. Output: {result.stdout}"
    assert result.stdout.strip() == "ALL TESTS PASSED", f"Expected 'ALL TESTS PASSED', got '{result.stdout.strip()}'"


def test_benchmark_result():
    result_path = "/home/user/benchmark_result.txt"
    assert os.path.isfile(result_path), f"Benchmark result file {result_path} does not exist."
    with open(result_path, "r") as f:
        content = f.read()
    assert content.strip() == "Parsed 100000 URLs", f"Expected 'Parsed 100000 URLs' in {result_path}, got '{content.strip()}'"

    benchmark = os.path.join(ROUTER_DIR, "benchmark.sh")
    assert os.path.isfile(benchmark), f"{benchmark} does not exist."
    assert os.access(benchmark, os.X_OK), f"{benchmark} is not executable."
    run = subprocess.run([benchmark], cwd=ROUTER_DIR, capture_output=True, text=True, timeout=15)
    assert run.returncode == 0, f"benchmark.sh failed:\nstdout: {run.stdout}\nstderr: {run.stderr}"
    assert run.stdout.strip() == content.strip(), f"Saved benchmark output does not match benchmark.sh stdout: {run.stdout!r}"
    assert run.stderr.strip(), "benchmark.sh did not emit timing statistics to stderr."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
