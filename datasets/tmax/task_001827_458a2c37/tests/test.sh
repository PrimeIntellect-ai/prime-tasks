#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

REPO = "/home/user/parser_repo"
PARSER_CPP = os.path.join(REPO, "parser.cpp")
FUZZ_TARGET = os.path.join(REPO, "fuzz_target.cc")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 120)
    return subprocess.run(cmd, **kwargs)


def test_recovered_token():
    token_path = "/home/user/recovered_token.txt"
    assert os.path.exists(token_path), f"{token_path} does not exist."
    with open(token_path, "r") as f:
        content = f.read().strip()
    assert content == "CRASH_TK_99", f"Expected 'CRASH_TK_99' in {token_path}, but got '{content}'."


def test_fuzz_target_exists_and_contains_entrypoint():
    assert os.path.exists(FUZZ_TARGET), f"{FUZZ_TARGET} does not exist."
    with open(FUZZ_TARGET, "r") as f:
        content = f.read()
    assert "LLVMFuzzerTestOneInput" in content, f"{FUZZ_TARGET} must contain LLVMFuzzerTestOneInput."


def test_fuzz_target_really_forwards_inputs_to_parser():
    # Link the submitted harness to a verifier-owned parse_data implementation.
    # Every independently generated input passed to the entrypoint must reach it.
    cases = [b"", b"CRASH_TK_99", b"CRASH_TK_99X", b"CRASH_TK_99" + bytes([255]) * 9]
    for _ in range(24):
        cases.append(secrets.token_bytes(secrets.randbelow(80)))

    case_literals = []
    for data in cases:
        values = ",".join(str(x) for x in data)
        case_literals.append("std::vector<uint8_t>{" + values + "}")

    checker = r'''
#include "parser.h"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t*, size_t);
static const uint8_t* expected_data;
static size_t expected_size;
static int calls;

void parse_data(const uint8_t* data, size_t size) {
    if (size != expected_size) std::abort();
    for (size_t i = 0; i < size; ++i) {
        if (data[i] != expected_data[i]) std::abort();
    }
    ++calls;
}

int main() {
    std::vector<std::vector<uint8_t>> cases = { CASES };
    for (const auto& input : cases) {
        expected_data = input.data();
        expected_size = input.size();
        calls = 0;
        LLVMFuzzerTestOneInput(input.data(), input.size());
        if (calls == 0) return 2;
    }
    return 0;
}
'''.replace("CASES", ",\n".join(case_literals))

    with tempfile.TemporaryDirectory() as tmpdir:
        checker_file = os.path.join(tmpdir, "checker.cpp")
        executable = os.path.join(tmpdir, "harness_check")
        with open(checker_file, "w") as f:
            f.write(checker)
        comp = run([
            "clang++", "-std=c++17", "-O1", checker_file, FUZZ_TARGET,
            "-I" + REPO, "-o", executable
        ])
        assert comp.returncode == 0, f"Fuzz harness does not compile with parser.h:\n{comp.stderr}"
        result = run([executable])
        assert result.returncode == 0, (
            "The fuzz entrypoint did not forward verifier-generated inputs to parse_data.\n"
            + result.stderr
        )


def test_parser_cpp_fixed_asan_on_boundary_and_generated_inputs():
    assert os.path.exists(PARSER_CPP), f"{PARSER_CPP} does not exist."

    # Retain the parser's original token-recognition logic rather than replacing
    # the implementation with an empty parse_data function.
    with open(PARSER_CPP, "r") as f:
        source = f.read()
    executable_source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert "CRASH_TK_99" in executable_source, "parser.cpp no longer contains the parser's token logic."
    assert "memcmp" in executable_source, "parser.cpp must preserve the existing token comparison."

    # Includes the original fixed 12-byte regression payload, every nearby
    # boundary length, both values of the post-token byte, and generated data.
    test_cpp = r'''
#include "parser.h"
#include <algorithm>
#include <cstdint>
#include <random>
#include <vector>

int main() {
    const uint8_t magic[] = {'C','R','A','S','H','_','T','K','_','9','9'};

    for (size_t n = 0; n <= 64; ++n) {
        std::vector<uint8_t> payload(n, 'X');
        for (size_t i = 0; i < std::min(n, sizeof(magic)); ++i) payload[i] = magic[i];
        parse_data(payload.data(), payload.size());
        if (n > 15) {
            payload[15] = 0xFF;
            parse_data(payload.data(), payload.size());
        }
    }

    std::mt19937_64 rng(0x91d3a72bULL);
    for (int trial = 0; trial < 2000; ++trial) {
        size_t n = static_cast<size_t>(rng() % 129);
        std::vector<uint8_t> payload(n);
        for (auto& b : payload) b = static_cast<uint8_t>(rng());
        if ((trial % 3) == 0 && n >= sizeof(magic)) {
            std::copy(magic, magic + sizeof(magic), payload.begin());
        }
        parse_data(payload.data(), payload.size());
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, "test.cpp")
        executable = os.path.join(tmpdir, "test_bin")
        with open(test_file, "w") as f:
            f.write(test_cpp)
        comp = run([
            "clang++", "-g", "-O1", "-fsanitize=address",
            test_file, PARSER_CPP, "-I" + REPO, "-o", executable
        ])
        assert comp.returncode == 0, f"Compilation with ASAN failed:\n{comp.stderr}"
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        result = run([executable], env=env)
        assert result.returncode == 0, f"Execution failed (likely an ASAN memory error):\n{result.stderr}"


def test_real_libfuzzer_runs_50000_iterations():
    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "fuzzer")
        corpus = os.path.join(tmpdir, "corpus")
        os.mkdir(corpus)
        seeds = [
            b"CRASH_TK_99",
            b"CRASH_TK_99X",
            b"CRASH_TK_99" + b"X" * 4,
            b"CRASH_TK_99" + b"X" * 5,
            b"CRASH_TK_99" + b"X" * 4 + b"\xff",
        ]
        for i, seed in enumerate(seeds):
            with open(os.path.join(corpus, f"seed{i}"), "wb") as f:
                f.write(seed)

        comp = run([
            "clang++", "-g", "-O1", "-fsanitize=fuzzer,address",
            FUZZ_TARGET, PARSER_CPP, "-I" + REPO, "-o", executable
        ])
        assert comp.returncode == 0, f"Required libFuzzer build failed:\n{comp.stderr}"

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        result = run([
            executable, corpus, "-runs=50000", "-seed=734921", "-print_final_stats=1"
        ], env=env)
        assert result.returncode == 0, f"libFuzzer failed before safely completing 50,000 runs:\n{result.stderr}"
        assert "stat::number_of_executed_units: 50000" in result.stderr, (
            "libFuzzer did not report completing exactly 50,000 executions.\n" + result.stderr
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
