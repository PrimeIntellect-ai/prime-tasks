#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest


def _run_filter(path, input_data):
    result = subprocess.run(
        [path],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"Filter {path} exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def _expected_filter_output(input_data):
    output = []
    for line in input_data.splitlines(keepends=True):
        content = line[:-1] if line.endswith(b"\n") else line
        if not content.startswith(b"/") and b"../" not in content:
            output.append(line)
    return b"".join(output)


def _behavioral_input():
    nonce = secrets.token_hex(16).encode("ascii")
    lines = [
        b"\n",
        b"safe/" + nonce + b".txt\n",
        b"/absolute/" + nonce + b"\n",
        b"../parent/" + nonce + b"\n",
        b"prefix../child/" + nonce + b"\n",
        b"safe/..\n",
        b"safe/..hidden/file\n",
        b"safe/. ./file\n",
        b"nested/path/file.o\n",
        b"double//slash\n",
    ]
    for _ in range(20):
        token = secrets.token_hex(12).encode("ascii")
        mode = secrets.randbelow(3)
        if mode == 0:
            lines.append(b"safe-" + token + b"/file\n")
        elif mode == 1:
            lines.append(b"/" + token + b"/file\n")
        else:
            lines.append(b"dir-" + token + b"/../file\n")
    lines.append(b"final-safe-" + nonce)
    return b"".join(lines)


def test_filter_c_exists():
    """Check if the filter.c source file exists."""
    path = "/home/user/filter.c"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."


def test_filter_executable_exists():
    """Check if the compiled filter executable exists and is executable."""
    path = "/home/user/filter"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_filter_source_and_executable_behavior():
    """Compile the submitted C source and exercise both resulting programs."""
    input_data = _behavioral_input()
    expected = _expected_filter_output(input_data)

    assert _run_filter("/home/user/filter", input_data) == expected, (
        "The submitted /home/user/filter does not implement the required filtering behavior."
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "filter-from-source")
        compile_result = subprocess.run(
            ["gcc", "/home/user/filter.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "/home/user/filter.c could not be compiled with gcc: "
            + compile_result.stderr.decode(errors="replace")
        )
        assert _run_filter(rebuilt, input_data) == expected, (
            "The program implemented by /home/user/filter.c does not perform the required filtering."
        )


def test_verified_artifacts_log_exists_and_correct():
    """Check if the verified_artifacts.log exists and contains the correct output."""
    path = "/home/user/verified_artifacts.log"
    assert os.path.exists(path), f"Log file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

    expected_lines = [
        "lib/math.obj",
        "include/math.h",
        "docs/readme.txt"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {path} do not match the expected output. "
        f"Expected: {expected_lines}, Got: {actual_lines}"
    )


def test_archive_pipeline_reproduces_log():
    """Run the archive listing through the submitted filter and extension rewrite."""
    tar_result = subprocess.run(
        ["tar", "-tf", "/home/user/artifacts/update.tar"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert tar_result.returncode == 0, (
        "tar could not list the update archive: "
        + tar_result.stderr.decode(errors="replace")
    )

    filtered = _run_filter("/home/user/filter", tar_result.stdout)
    sed_result = subprocess.run(
        ["sed", r"s/\.o$/.obj/"],
        input=filtered,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert sed_result.returncode == 0, (
        "sed extension transformation failed: "
        + sed_result.stderr.decode(errors="replace")
    )

    generated_lines = [
        line.strip()
        for line in sed_result.stdout.decode().splitlines()
        if line.strip()
    ]
    with open("/home/user/verified_artifacts.log", "r") as f:
        logged_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert generated_lines == logged_lines, (
        "Running the required tar/filter/sed pipeline does not reproduce "
        "/home/user/verified_artifacts.log."
    )


def test_archive_not_extracted():
    """Ensure the archive was not extracted."""
    unexpected_paths = [
        "/home/user/lib",
        "/home/user/include",
        "/home/user/docs",
        "/home/user/artifacts/lib",
        "/home/user/artifacts/include",
        "/home/user/artifacts/docs"
    ]
    for path in unexpected_paths:
        assert not os.path.exists(path), f"Archive appears to be extracted; found {path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
