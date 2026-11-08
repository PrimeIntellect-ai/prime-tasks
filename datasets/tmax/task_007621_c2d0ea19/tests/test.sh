#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import tempfile


def test_filter_c_exists():
    """Verify that the C source file exists."""
    path = "/home/user/filter.c"
    assert os.path.isfile(path), f"Expected C source file {path} does not exist."


def test_filter_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    path = "/home/user/filter"
    assert os.path.isfile(path), f"Expected executable {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {path} is not a compiled executable."


def test_fatal_errors_log_content():
    """Verify the output log contains exactly the FATAL error blocks from the raw log."""
    raw_log_path = "/home/user/raw_docs.log"
    output_log_path = "/home/user/fatal_errors.log"

    assert os.path.isfile(raw_log_path), f"Raw log file {raw_log_path} is missing."
    assert os.path.isfile(output_log_path), f"Output file {output_log_path} does not exist."

    expected_lines = []
    current_block = []
    in_block = False
    has_fatal = False

    with open(raw_log_path, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped == "[DOC-ERROR]":
                in_block = True
                current_block = [line]
                has_fatal = False
            elif in_block:
                current_block.append(line)
                if line.startswith("Severity: FATAL"):
                    has_fatal = True
                if stripped == "[END-ERROR]":
                    in_block = False
                    if has_fatal:
                        expected_lines.extend(current_block)

    with open(output_log_path, "r") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, (
        f"The content of {output_log_path} does not match the expected output. "
        "It should contain only the blocks with 'Severity: FATAL' exactly as they appeared in the raw log."
    )


def run_filter(path, input_data):
    result = subprocess.run(
        [path],
        input=input_data.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout.decode()


def test_source_compiles_and_filter_handles_unseen_stream():
    """Compile the submitted source and exercise both it and the installed executable."""
    token = secrets.token_hex(16)
    warn_block = (
        "[DOC-ERROR]\n"
        f"File: warn-{token}.md\n"
        f"Message: warning-{token}\n"
        "Severity: WARN\n"
        "[END-ERROR]\n"
    )
    fatal_block_1 = (
        "[DOC-ERROR]\n"
        f"File: fatal-a-{token}.md\n"
        f"Message: first-{token}\n"
        "Severity: FATAL\n"
        "Detail: preserve this line exactly\n"
        "[END-ERROR]\n"
    )
    nonmatching_block = (
        "[DOC-ERROR]\n"
        f"File: indented-{token}.md\n"
        " Severity: FATAL\n"
        "[END-ERROR]\n"
    )
    fatal_block_2 = (
        "[DOC-ERROR]\n"
        f"File: fatal-b-{token}.md\n"
        "Severity: FATAL: subsystem unavailable\n"
        f"Message: second-{token}\n"
        "[END-ERROR]\n"
    )
    input_data = (
        f"ordinary output {token}\n"
        + warn_block
        + f"more ordinary output {token}\n"
        + fatal_block_1
        + nonmatching_block
        + fatal_block_2
        + "build complete\n"
    )
    expected = fatal_block_1 + fatal_block_2

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "filter-from-source")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "/home/user/filter.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "The submitted filter.c did not compile: "
            + compile_result.stderr.decode(errors="replace")
        )
        assert run_filter(rebuilt, input_data) == expected, (
            "The program compiled from filter.c did not correctly filter an unseen input stream."
        )

    assert run_filter("/home/user/filter", input_data) == expected, (
        "The installed /home/user/filter did not correctly filter an unseen input stream."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
