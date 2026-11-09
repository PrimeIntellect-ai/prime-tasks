#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

FASTA = "/home/user/proteins.fasta"
SOURCE = "/home/user/simulate.c"
EXECUTABLE = "/home/user/simulate"
RESULTS = "/home/user/simulation_results.txt"


class LCG:
    def __init__(self):
        self.seed = 12345

    def get_rand(self):
        self.seed = (self.seed * 1103515245 + 12345) % 2147483648
        return self.seed / 2147483648.0


def compute_expected_mean_lcc():
    lcg = LCG()
    iterations = 10000
    p = 0.25

    # Based on the prefix rule (length >= 3) for the given FASTA:
    # Seq0, Seq1, Seq3, Seq7 -> MKV
    # Seq2, Seq4, Seq8 -> MKA
    # Seq5, Seq6, Seq9 -> MLK
    cliques = [
        [0, 1, 3, 7],
        [2, 4, 8],
        [5, 6, 9],
    ]

    total_lcc = 0
    for _ in range(iterations):
        active = set()
        for i in range(10):
            if lcg.get_rand() >= p:
                active.add(i)

        max_comp = 0
        for clique in cliques:
            comp_size = sum(1 for node in clique if node in active)
            if comp_size > max_comp:
                max_comp = comp_size
        total_lcc += max_comp

    return f"Mean LCC: {total_lcc / iterations:.4f}"


def expected_for_sequences(sequences):
    n = len(sequences)
    adjacency = [[] for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            common = 0
            for a, b in zip(sequences[i], sequences[j]):
                if a != b:
                    break
                common += 1
            if common >= 3:
                adjacency[i].append(j)
                adjacency[j].append(i)

    lcg = LCG()
    total = 0
    for _ in range(10000):
        active = [lcg.get_rand() >= 0.25 for _ in range(n)]
        seen = [False] * n
        largest = 0
        for start in range(n):
            if not active[start] or seen[start]:
                continue
            seen[start] = True
            stack = [start]
            size = 0
            while stack:
                node = stack.pop()
                size += 1
                for neighbor in adjacency[node]:
                    if active[neighbor] and not seen[neighbor]:
                        seen[neighbor] = True
                        stack.append(neighbor)
            largest = max(largest, size)
        total += largest
    return f"Mean LCC: {total / 10000:.4f}"


def write_fasta(sequences):
    with open(FASTA, "w") as f:
        for i, sequence in enumerate(sequences):
            f.write(f">Dynamic{i}\n{sequence}\n")


def run_and_check(executable, sequences):
    write_fasta(sequences)
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert completed.returncode == 0, (
        f"{executable} failed with status {completed.returncode}: {completed.stderr}"
    )
    assert os.path.exists(RESULTS), f"{executable} did not create {RESULTS}"
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a regular file"
    with open(RESULTS) as f:
        actual = f.read().strip()
    expected = expected_for_sequences(sequences)
    assert actual == expected, (
        f"For dynamic FASTA input, expected '{expected}', but {executable} produced '{actual}'."
    )


def test_c_source_code_exists():
    assert os.path.exists(SOURCE), f"The C source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"The executable {EXECUTABLE} does not exist. Did you compile the code?"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_simulation_results():
    assert os.path.exists(RESULTS), f"The results file {RESULTS} does not exist."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a regular file."
    with open(RESULTS) as f:
        content = f.read().strip()
    expected_result = compute_expected_mean_lcc()
    assert content == expected_result, f"Expected '{expected_result}', but found '{content}' in {RESULTS}."


def test_source_compiles_and_both_artifacts_process_fasta():
    compiled = "/tmp/simulate_from_submitted_source"
    build = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", compiled],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"Submitted C source failed to compile:\n{build.stderr}"

    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    original_fasta = open(FASTA, "rb").read()
    original_results = open(RESULTS, "rb").read() if os.path.isfile(RESULTS) else None

    alphabet = "ACDEFGHIKLMNPQRSTVWY"
    rng = secrets.SystemRandom()
    prefixes = set()
    while len(prefixes) < 5:
        prefixes.add("".join(rng.choice(alphabet) for _ in range(3)))
    prefixes = list(prefixes)
    assignments = [0, 1, 0, 2, 3, 1, 4, 2, 0, 4, 3, 1, 2, 4, 0, 3, 1]
    random_case = [
        prefixes[group] + "".join(rng.choice(alphabet) for _ in range(rng.randrange(2, 9)))
        for group in assignments
    ]

    cases = [
        ["AAAAA"],
        ["QQQAAA", "RSTAAA", "QQQBBB", "LMNCCC", "RSTDDD", "QQQCCC", "XYZAAA"],
        random_case,
    ]

    try:
        for executable in (EXECUTABLE, compiled):
            for sequences in cases:
                run_and_check(executable, sequences)
    finally:
        with open(FASTA, "wb") as f:
            f.write(original_fasta)
        if original_results is None:
            if os.path.lexists(RESULTS):
                os.remove(RESULTS)
        else:
            with open(RESULTS, "wb") as f:
                f.write(original_results)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
