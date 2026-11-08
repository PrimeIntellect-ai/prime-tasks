#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

SOURCE = "/home/user/api_parser.c"
EXECUTABLE = "/home/user/api_parser"
FUZZ_SCRIPT = "/home/user/fuzz.sh"
FUZZ_INPUT = "/home/user/test.bin"
FUZZ_LOG = "/home/user/fuzz_result.log"


def run_parser(executable, data, tmp_path, name):
    test_file = tmp_path / name
    test_file.write_bytes(data)
    try:
        return subprocess.run(
            [str(executable), str(test_file)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out on {name}")


@pytest.fixture(scope="session")
def rebuilt_parser(tmp_path_factory):
    """Compile the submitted source independently so source and installed binary are both tested."""
    output = tmp_path_factory.mktemp("build") / "api_parser_from_source"
    result = subprocess.run(
        ["gcc", "-O0", "-Wall", "-Wextra", SOURCE, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Submitted C source does not compile:\n{result.stderr}"
    assert output.read_bytes()[:4] == b"\x7fELF", "gcc did not produce a native ELF executable"
    return output


def test_api_parser_compiled_and_executable():
    """Verify that the C program was compiled to the correct path and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Compiled binary {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"Compiled binary {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted parser is not a compiled ELF binary."


def test_api_parser_c_modified_for_bounds_checking():
    """Retain the source assertion and ensure the submitted source can be compiled."""
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "49" in content, "The C source code does not seem to contain the logic to cap the length to 49."


def test_submitted_source_compiles(rebuilt_parser):
    assert os.path.isfile(rebuilt_parser)
    assert os.access(rebuilt_parser, os.X_OK)


@pytest.mark.parametrize("which", ["installed", "rebuilt"])
def test_parser_enforces_49_byte_boundary(which, rebuilt_parser, tmp_path):
    """Exercise both artifacts on derived boundary and randomized cases.

    For L > 49, a file containing exactly 49 payload bytes must be accepted, proving
    the parser does not still demand L bytes. One byte fewer must be rejected,
    proving it really attempts to copy 49 rather than simply returning success.
    """
    executable = EXECUTABLE if which == "installed" else rebuilt_parser
    lengths = [0, 1, 2, 48, 49, 50, 51, 127, 254, 255]
    lengths.extend(secrets.randbelow(256) for _ in range(8))

    for index, declared_length in enumerate(lengths):
        capped = min(declared_length, 49)
        payload = secrets.token_bytes(capped)
        result = run_parser(
            executable,
            bytes([declared_length]) + payload,
            tmp_path,
            f"{which}_exact_{index}_{declared_length}.bin",
        )
        assert result.returncode == 0, (
            f"Parser rejected L={declared_length} with the required {capped} bytes; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        if capped > 0:
            result = run_parser(
                executable,
                bytes([declared_length]) + payload[:-1],
                tmp_path,
                f"{which}_short_{index}_{declared_length}.bin",
            )
            assert result.returncode != 0, (
                f"Parser accepted a truncated payload for L={declared_length}; "
                "it does not appear to copy the capped number of bytes."
            )

        full_payload = secrets.token_bytes(declared_length)
        result = run_parser(
            executable,
            bytes([declared_length]) + full_payload,
            tmp_path,
            f"{which}_full_{index}_{declared_length}.bin",
        )
        assert result.returncode == 0, (
            f"Parser failed on a complete payload with L={declared_length}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def test_api_parser_no_segfault_on_large_payload(tmp_path):
    """Retain the original 255-byte behavioral assertion."""
    result = run_parser(EXECUTABLE, b"\xff" + b"A" * 255, tmp_path, "check.bin")
    assert result.returncode == 0, (
        f"Expected exit code 0, but got {result.returncode}. The program might still be crashing."
    )


def test_fuzz_script_exists():
    """Verify that the fuzzing script exists and is valid bash."""
    assert os.path.isfile(FUZZ_SCRIPT), f"Fuzzing script {FUZZ_SCRIPT} does not exist."
    result = subprocess.run(["bash", "-n", FUZZ_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Fuzzing script is not valid bash: {result.stderr}"


def execute_fuzzer():
    for path in (FUZZ_INPUT, FUZZ_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    try:
        result = subprocess.run(
            ["bash", FUZZ_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The fuzzing script timed out.")
    assert result.returncode == 0, (
        f"The fuzzing script failed with {result.returncode}: stderr={result.stderr!r}"
    )
    assert os.path.isfile(FUZZ_INPUT), "The fuzzer did not generate /home/user/test.bin."
    data = open(FUZZ_INPUT, "rb").read()
    assert len(data) == 256, f"Fuzzer input must be 256 bytes, found {len(data)}."
    assert data[0] == 255, "The first fuzz input byte must be 0xFF."
    assert os.path.isfile(FUZZ_LOG), "The fuzzer did not generate /home/user/fuzz_result.log."
    content = open(FUZZ_LOG, "r").read().strip()
    assert "SUCCESS" in content, f"Log file does not contain 'SUCCESS'. Found: {content}"
    return data


def test_fuzzer_really_runs_and_generates_random_payloads():
    """Run the submitted fuzzer from a clean state and validate its artifacts twice."""
    first = execute_fuzzer()
    second = execute_fuzzer()
    assert first[1:] != second[1:], "The fuzzer generated the same payload twice; payload bytes are not random."


def test_fuzz_result_log():
    """Retain the original final log assertion."""
    assert os.path.isfile(FUZZ_LOG), f"Log file {FUZZ_LOG} does not exist. Did you run the fuzzer?"
    with open(FUZZ_LOG, "r") as f:
        content = f.read().strip()
    assert "SUCCESS" in content, f"Log file {FUZZ_LOG} does not contain 'SUCCESS'. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
