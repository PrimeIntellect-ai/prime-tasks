#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

HOME = "/home/user"
CPP = os.path.join(HOME, "mc_motif.cpp")
MAKEFILE = os.path.join(HOME, "Makefile")
EXE = os.path.join(HOME, "mc_motif")
RESULT = os.path.join(HOME, "result.txt")
REFERENCE = os.path.join(HOME, "reference.fasta")

ORACLE_CPP = r'''
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <string>

int main(int argc, char **argv) {
    if (argc != 6) return 2;

    std::ifstream in(argv[1]);
    if (!in) return 3;

    std::string ref, line;
    while (std::getline(in, line)) {
        if (!line.empty() && line[0] == '>') continue;
        for (unsigned char c : line) {
            if (!std::isspace(c)) ref.push_back(static_cast<char>(c));
        }
    }

    const std::string motif = argv[2];
    const uint32_t rate = static_cast<uint32_t>(std::stoul(argv[3]));
    const uint32_t iterations = static_cast<uint32_t>(std::stoul(argv[4]));
    const uint32_t seed = static_cast<uint32_t>(std::stoul(argv[5]));
    std::mt19937 rng(seed);
    unsigned long long total = 0;

    for (uint32_t i = 0; i < iterations; ++i) {
        std::string mutated = ref;
        for (size_t j = 0; j < mutated.size(); ++j) {
            uint32_t r1 = rng();
            if (r1 % 100 < rate) {
                uint32_t r2 = rng();
                char pool[3];
                int n = 0;
                if (mutated[j] != 'A') pool[n++] = 'A';
                if (mutated[j] != 'C') pool[n++] = 'C';
                if (mutated[j] != 'G') pool[n++] = 'G';
                if (mutated[j] != 'T') pool[n++] = 'T';
                mutated[j] = pool[r2 % 3];
            }
        }
        size_t pos = 0;
        while ((pos = mutated.find(motif, pos)) != std::string::npos) {
            ++total;
            ++pos;
        }
    }

    std::cout << std::fixed << std::setprecision(4)
              << static_cast<double>(total) / iterations << '\n';
    return 0;
}
'''


def run_checked(command, timeout=30):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert os.path.exists(CPP), f"File {CPP} does not exist."
    assert os.path.isfile(CPP), f"Path {CPP} is not a file."
    assert os.path.exists(MAKEFILE), f"File {MAKEFILE} does not exist."
    assert os.path.isfile(MAKEFILE), f"Path {MAKEFILE} is not a file."

    dry = run_checked(["make", "-n", "-B", "mc_motif"], timeout=10)
    assert dry.returncode == 0, f"Makefile cannot build mc_motif:\n{dry.stdout}{dry.stderr}"
    build_recipe = dry.stdout + dry.stderr
    assert re.search(r"(^|[/\s])g\+\+(\s|$)", build_recipe), "Makefile must compile with g++."
    assert "-O3" in build_recipe, "Makefile must use the -O3 optimization flag."
    assert "mc_motif.cpp" in build_recipe, "Makefile must compile mc_motif.cpp."

    if os.path.lexists(EXE):
        os.remove(EXE)
    built = run_checked(["make", "-B", "mc_motif"], timeout=30)
    assert built.returncode == 0, f"Build failed:\n{built.stdout}{built.stderr}"
    assert os.path.isfile(EXE), "Makefile did not create /home/user/mc_motif."
    assert os.access(EXE, os.X_OK), "mc_motif is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mc_motif must be a compiled native executable."


@pytest.fixture(scope="session")
def oracle_exe():
    tmpdir = tempfile.TemporaryDirectory()
    src = os.path.join(tmpdir.name, "oracle.cpp")
    exe = os.path.join(tmpdir.name, "oracle")
    with open(src, "w") as f:
        f.write(ORACLE_CPP)
    proc = run_checked(["g++", "-O3", src, "-o", exe], timeout=30)
    assert proc.returncode == 0, f"Failed to compile verifier oracle: {proc.stderr}"
    yield exe
    tmpdir.cleanup()


def expected_output(oracle, fasta, motif, rate, iterations, seed):
    proc = run_checked(
        [oracle, fasta, motif, str(rate), str(iterations), str(seed)], timeout=30
    )
    assert proc.returncode == 0, f"Verifier oracle failed: {proc.stderr}"
    return proc.stdout


def check_case(oracle, fasta, motif, rate, iterations, seed):
    expected = expected_output(oracle, fasta, motif, rate, iterations, seed)
    proc = run_checked(
        [EXE, fasta, motif, str(rate), str(iterations), str(seed)], timeout=30
    )
    assert proc.returncode == 0, (
        f"mc_motif failed for motif={motif}, rate={rate}, iterations={iterations}, "
        f"seed={seed}: {proc.stderr}"
    )
    assert proc.stderr == "", f"mc_motif unexpectedly wrote to stderr: {proc.stderr!r}"
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n", proc.stdout), (
        f"Output is not formatted to exactly four decimal places: {proc.stdout!r}"
    )
    assert proc.stdout == expected, f"Expected {expected!r}, got {proc.stdout!r}."


def write_fasta(path, sequence, split_points=None, internal_spaces=False):
    if split_points is None:
        split_points = [len(sequence)]
    chunks = []
    start = 0
    for end in split_points:
        chunk = sequence[start:end]
        if internal_spaces and len(chunk) > 3:
            chunk = chunk[:2] + " \t" + chunk[2:]
        chunks.append(chunk)
        start = end
    if start < len(sequence):
        chunks.append(sequence[start:])
    with open(path, "w") as f:
        f.write(">generated verifier input\n")
        f.write("\n".join(chunks))
        f.write("\n")


def test_mc_motif_cpp_exists():
    assert os.path.exists(CPP), f"File {CPP} does not exist."
    assert os.path.isfile(CPP), f"Path {CPP} is not a file."


def test_makefile_exists():
    assert os.path.exists(MAKEFILE), f"File {MAKEFILE} does not exist."
    assert os.path.isfile(MAKEFILE), f"Path {MAKEFILE} is not a file."


def test_result_txt_is_correct_and_matches_executable(oracle_exe):
    assert os.path.exists(RESULT), f"File {RESULT} does not exist."
    assert os.path.isfile(RESULT), f"Path {RESULT} is not a file."

    expected = expected_output(oracle_exe, REFERENCE, "GATTACA", 15, 10000, 42)
    with open(RESULT, "r") as f:
        actual = f.read()
    assert actual.strip() == expected.strip(), (
        f"result.txt content is incorrect. Expected {expected.strip()!r}, "
        f"got {actual.strip()!r}."
    )

    proc = run_checked([EXE, REFERENCE, "GATTACA", "15", "10000", "42"], timeout=60)
    assert proc.returncode == 0, f"Required pipeline invocation failed: {proc.stderr}"
    assert proc.stdout == expected, "The built tool does not produce the required pipeline result."
    assert actual == proc.stdout, "result.txt must be the exact stdout of the required run."


def test_curated_functional_cases(oracle_exe):
    with tempfile.TemporaryDirectory() as tmp:
        cases = [
            ("AAAAAA", "AAA", 0, 4, 1, [2, 4, 6], True),
            ("ACGTACGTGATTACA", "A", 100, 11, 987654321, [4, 9, 15], False),
            ("GATTACAGATTACA", "GATTACA", 37, 29, 0, [7, 14], True),
            ("CCCCGGGGAAAATTTT", "CG", 1, 53, 4294967295, [3, 10, 16], False),
        ]
        for i, (seq, motif, rate, iterations, seed, splits, spaces) in enumerate(cases):
            fasta = os.path.join(tmp, f"case_{i}.fasta")
            write_fasta(fasta, seq, splits, spaces)
            check_case(oracle_exe, fasta, motif, rate, iterations, seed)


def test_runtime_generated_functional_cases(oracle_exe):
    alphabet = "ACGT"
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(6):
            length = rng.randint(18, 95)
            sequence = "".join(rng.choice(alphabet) for _ in range(length))
            motif_len = rng.randint(1, min(9, length))
            motif = "".join(rng.choice(alphabet) for _ in range(motif_len))
            rate = rng.randint(2, 98)
            iterations = rng.randint(5, 80)
            seed = rng.randrange(0, 2**32)
            cut1 = rng.randint(1, length - 1)
            cut2 = rng.randint(cut1, length)
            fasta = os.path.join(tmp, f"random_{i}.fasta")
            write_fasta(fasta, sequence, [cut1, cut2, length], i % 2 == 0)
            check_case(oracle_exe, fasta, motif, rate, iterations, seed)


def test_requires_exactly_five_arguments():
    too_few = run_checked([EXE, REFERENCE, "GATTACA", "15", "10"], timeout=5)
    too_many = run_checked(
        [EXE, REFERENCE, "GATTACA", "15", "10", "42", "extra"], timeout=5
    )
    assert too_few.returncode != 0, "mc_motif must reject fewer than five arguments."
    assert too_many.returncode != 0, "mc_motif must reject more than five arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
