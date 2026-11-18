#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/archiver_oracle"
AGENT_PATH = "/home/user/archiver"
SOURCE_PATH = "/home/user/archiver.cpp"
LIB_DIR = "/app/liblogpack-1.2"
LIB_PATH = os.path.join(LIB_DIR, "liblogpack.a")
REBUILT_PATH = "/tmp/archiver_rebuilt"
PROBE_PATH = "/tmp/archiver_probe"
N_TESTS = 50


def run_program(path, input_bytes, label):
    try:
        return subprocess.run(
            [path], input=input_bytes, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5, check=True
        ).stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"{label} failed with stderr: {e.stderr.decode(errors='replace')}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"{label} timed out")


def expected_archive(data, xor_key):
    result = bytearray(b"PACKv1\0\0")
    for offset in range(0, len(data), 4096):
        chunk = data[offset:offset + 4096]
        payload = bytes(value ^ xor_key for value in chunk)
        result += len(chunk).to_bytes(2, "little")
        result += len(payload).to_bytes(2, "little")
        result += payload
    return bytes(result)


@pytest.fixture(scope="session", autouse=True)
def verify_build_artifacts():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"
    assert not os.path.islink(AGENT_PATH), "Agent executable must not be a symlink"
    assert os.path.isfile(SOURCE_PATH), f"Required source file not found at {SOURCE_PATH}"

    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable at {ORACLE_PATH} is not executable"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent executable aliases the oracle"
    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent executable is a copy of the oracle"

    build = subprocess.run(
        ["make", "-C", LIB_DIR, "clean", "all"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert build.returncode == 0, f"liblogpack Makefile build failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(LIB_PATH), f"Static library not produced at {LIB_PATH}"

    archive = subprocess.run(
        ["ar", "t", LIB_PATH], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    assert archive.returncode == 0 and archive.stdout.strip(), "liblogpack.a is not a valid nonempty archive"

    lib_symbols = subprocess.run(
        ["nm", "-C", LIB_PATH], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, check=True
    ).stdout
    assert "pack_data(" in lib_symbols, "liblogpack.a does not provide pack_data"

    obj_path = "/tmp/archiver_submission.o"
    compile_obj = subprocess.run(
        ["g++", "-O2", "-Wall", "-I" + LIB_DIR, "-c", SOURCE_PATH, "-o", obj_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_obj.returncode == 0, f"archiver.cpp failed to compile:\n{compile_obj.stdout}\n{compile_obj.stderr}"

    obj_symbols = subprocess.run(
        ["nm", "-C", obj_path], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, check=True
    ).stdout
    assert any(" U pack_data(" in line for line in obj_symbols.splitlines()), \
        "archiver.cpp does not call the external pack_data function"

    link = subprocess.run(
        ["g++", obj_path, LIB_PATH, "-o", REBUILT_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert link.returncode == 0, f"archiver.cpp could not be linked with liblogpack.a:\n{link.stdout}\n{link.stderr}"

    probe_source = "/tmp/logpack_probe.cpp"
    with open(probe_source, "w") as probe:
        probe.write(r'''#include <cstddef>
void pack_data(const unsigned char* in, size_t in_len, unsigned char* out, size_t* out_len) {
    for (size_t i = 0; i < in_len; ++i) out[i] = in[i] ^ 0xA7;
    *out_len = in_len;
}
''')
    probe_link = subprocess.run(
        ["g++", obj_path, probe_source, "-o", PROBE_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert probe_link.returncode == 0, f"Could not instrument pack_data usage:\n{probe_link.stdout}\n{probe_link.stderr}"

    probe_data = bytes((i * 37 + 11) & 0xFF for i in range(5003))
    probe_input = probe_data.hex().upper().encode("ascii")
    probe_output = run_program(PROBE_PATH, probe_input, "Instrumented archiver")
    assert probe_output == expected_archive(probe_data, 0xA7), \
        "archiver.cpp does not use pack_data output to construct each archive chunk"


@pytest.mark.parametrize("i", range(N_TESTS))
def test_fuzz_equivalence(i):
    random.seed(42 + i)
    length = random.randint(5, 50000) * 2
    hex_chars = "0123456789ABCDEF"
    input_str = "".join(random.choice(hex_chars) for _ in range(length))
    input_bytes = input_str.encode("ascii")

    oracle_out = run_program(ORACLE_PATH, input_bytes, f"Oracle on test {i}")

    for tested_path, label in ((AGENT_PATH, "Agent"), (REBUILT_PATH, "Rebuilt source")):
        agent_out = run_program(tested_path, input_bytes, f"{label} on test {i}")
        if oracle_out != agent_out:
            mismatch_len = min(len(oracle_out), len(agent_out))
            diff_idx = next(
                (idx for idx in range(mismatch_len) if oracle_out[idx] != agent_out[idx]),
                mismatch_len
            )
            snippet_start = max(0, diff_idx - 16)
            snippet_end = min(max(len(oracle_out), len(agent_out)), diff_idx + 16)
            pytest.fail(
                f"{label} output mismatch on test {i} (input length {length}).\n"
                f"Oracle output length: {len(oracle_out)}, output length: {len(agent_out)}\n"
                f"First difference at byte {diff_idx}.\n"
                f"Oracle snippet around diff: {oracle_out[snippet_start:snippet_end].hex()}\n"
                f"Output snippet around diff: {agent_out[snippet_start:snippet_end].hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
