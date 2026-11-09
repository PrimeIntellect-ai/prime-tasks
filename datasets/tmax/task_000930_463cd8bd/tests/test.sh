#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import struct
import subprocess
import pytest

ROOT = "/home/user/math_port"
ROUTER = os.path.join(ROOT, "math_router")
LIBRARY = os.path.join(ROOT, "libmathops.so")


def router_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = ROOT + ":" + env.get("LD_LIBRARY_PATH", "")
    return env


def expected_output(seq1, seq2):
    values = sorted(seq1 + seq2)
    return '{"result": [' + ", ".join(str(value) for value in values) + ']}\n'


def make_url(seq1, seq2, reverse_parameters=False):
    first = ",".join(map(str, seq1))
    second = ",".join(map(str, seq2))
    if reverse_parameters:
        return f"/math/merge?seq2={second}&seq1={first}"
    return f"/math/merge?seq1={first}&seq2={second}"


def run_router(url):
    return subprocess.run(
        [ROUTER, url],
        capture_output=True,
        text=True,
        env=router_env(),
        timeout=10,
    )


def elf_type(path):
    with open(path, "rb") as handle:
        header = handle.read(18)
    assert len(header) >= 18 and header[:4] == b"\x7fELF", f"{path} is not an ELF file."
    assert header[5] in (1, 2), f"{path} has an invalid ELF byte order."
    byte_order = "<" if header[5] == 1 else ">"
    return struct.unpack(byte_order + "H", header[16:18])[0]


def test_libmathops_exists():
    """Test that the shared library libmathops.so was created."""
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} is missing."
    assert elf_type(LIBRARY) == 3, f"{LIBRARY} is not an ELF shared object."


def test_math_router_exists_and_linked():
    """Test that math_router exists and is dynamically linked to libmathops.so."""
    assert os.path.isfile(ROUTER), f"Executable {ROUTER} is missing."
    assert os.access(ROUTER, os.X_OK), f"Executable {ROUTER} is not executable."
    assert elf_type(ROUTER) in (2, 3), f"{ROUTER} is not an ELF executable."

    # Preserve the original dynamic-linkage assertion.
    ldd_out = subprocess.run(["ldd", ROUTER], capture_output=True, text=True)
    assert "libmathops.so" in ldd_out.stdout, "math_router is not dynamically linked against libmathops.so."

    dynamic = subprocess.run(["readelf", "-d", ROUTER], capture_output=True, text=True)
    assert dynamic.returncode == 0, f"Unable to inspect {ROUTER} as a dynamic executable."
    assert "libmathops.so" in dynamic.stdout, "math_router has no dynamic dependency on libmathops.so."


def test_container_out_json():
    """Test that the output JSON matches the expected sorted sequence."""
    out_path = "/home/user/container_out.json"
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."

    with open(out_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{out_path} does not contain valid JSON.")

    expected = {"result": [4, 8, 15, 16, 23, 42]}
    assert data == expected, f"Content of {out_path} is incorrect. Expected {expected}, got {data}."

    # Ensure the saved artifact is exactly the strict MINIMAL_CONTAINER output
    # currently produced by the submitted executable for the required request.
    url = "/math/merge?seq1=42,15,8&seq2=4,16,23"
    result = run_router(url)
    assert result.returncode == 0, f"math_router failed: {result.stderr}"
    assert result.stderr == "", f"math_router emitted unexpected stderr: {result.stderr}"
    assert result.stdout == expected_output([42, 15, 8], [4, 16, 23])
    with open(out_path, "r") as f:
        assert f.read() == result.stdout, "container_out.json does not match math_router stdout."


def test_router_parses_merges_sorts_and_uses_strict_json():
    """Exercise behavior on verifier-generated inputs rather than a fixed answer."""
    rng = random.SystemRandom()
    cases = [
        ([9, -4, 9, 0], [3, -11, 3]),
        (list(range(25, 4, -2)), [8, -2, 17, 8, 100, -30]),
    ]
    for _ in range(4):
        len1 = rng.randint(3, 22)
        len2 = rng.randint(3, 22)
        seq1 = [rng.randint(-5000, 5000) for _ in range(len1)]
        seq2 = [rng.randint(-5000, 5000) for _ in range(len2)]
        cases.append((seq1, seq2))

    for index, (seq1, seq2) in enumerate(cases):
        url = make_url(seq1, seq2, reverse_parameters=(index % 2 == 1))
        result = run_router(url)
        assert result.returncode == 0, f"math_router failed for {url}: {result.stderr}"
        assert result.stderr == "", f"math_router emitted unexpected stderr for {url}: {result.stderr}"
        expected = expected_output(seq1, seq2)
        assert result.stdout == expected, f"Incorrect strict JSON output for {url}. Expected {expected!r}, got {result.stdout!r}."
        assert json.loads(result.stdout) == {"result": sorted(seq1 + seq2)}


def test_valgrind_no_leaks():
    """Test that running the executable through Valgrind reports no leaks."""
    assert os.path.isfile(ROUTER), f"Executable {ROUTER} is missing."

    # Preserve the exact required Valgrind invocation and additionally verify its stdout.
    cmd = [
        "valgrind",
        "--leak-check=full",
        "--error-exitcode=1",
        ROUTER,
        "/math/merge?seq1=42,15,8&seq2=4,16,23",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, env=router_env(), timeout=30)
    assert result.returncode == 0, f"Valgrind reported memory leaks or execution failed. stderr:\n{result.stderr}"
    assert result.stdout == expected_output([42, 15, 8], [4, 16, 23]), "Valgrind execution produced incorrect router output."

    # Exercise all allocation/reallocation paths under Valgrind with an input
    # generated only when verification runs.
    rng = random.SystemRandom()
    seq1 = [rng.randint(-10000, 10000) for _ in range(24)]
    seq2 = [rng.randint(-10000, 10000) for _ in range(19)]
    url = make_url(seq1, seq2)
    extra = subprocess.run(
        ["valgrind", "--leak-check=full", "--error-exitcode=1", ROUTER, url],
        capture_output=True,
        text=True,
        env=router_env(),
        timeout=30,
    )
    assert extra.returncode == 0, f"Valgrind failed on generated input. stderr:\n{extra.stderr}"
    assert extra.stdout == expected_output(seq1, seq2), "Valgrind execution failed behavioral verification."


def test_api_diff():
    """Test that the API diff file exists and contains the correct unified diff output."""
    diff_path = "/home/user/api_diff.txt"
    assert os.path.isfile(diff_path), f"Diff file {diff_path} is missing."

    with open(diff_path, "r") as f:
        content = f.read()

    # Preserve the original unified-diff assertions.
    expected_removed = '-{"result": [1, 4, 8, 15, 16, 23, 42]}'
    expected_added = '+{"result": [4, 8, 15, 16, 23, 42]}'
    assert expected_removed in content, f"api_diff.txt is missing the expected removed line: {expected_removed}"
    assert expected_added in content, f"api_diff.txt is missing the expected added line: {expected_added}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
