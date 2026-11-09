#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

PROJECT = "/home/user/seq_match"
DATASET = "/home/user/dataset.txt"
RESULT = "/home/user/result.txt"
BINARY = os.path.join(PROJECT, "target", "release", "seq_match")
CARGO = "/root/.cargo/bin/cargo"


def test_result_file_exists():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"Result file is missing at {result_path}"
    assert os.path.isfile(result_path), f"{result_path} is not a file"


def test_result_content():
    result_path = "/home/user/result.txt"
    with open(result_path, "r") as f:
        content = f.read().strip()
    expected = "42,1337,2"
    assert content == expected, f"Expected result '{expected}', but got '{content}'"


def test_rust_project_exists():
    assert os.path.isdir(PROJECT), f"Rust project directory missing at {PROJECT}"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml missing"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "main.rs missing"


def test_rayon_dependency():
    cargo_toml = os.path.join(PROJECT, "Cargo.toml")
    with open(cargo_toml, "r") as f:
        content = f.read()
    assert "rayon" in content, "The 'rayon' crate is missing from Cargo.toml"


def compile_oracle():
    source = r'''
#include <climits>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::ifstream in(argv[1]);
    std::vector<std::string> s;
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!line.empty()) s.push_back(line);
    }
    int best = INT_MAX;
    size_t bi = 0, bj = 0;
    for (size_t i = 0; i < s.size(); ++i) {
        for (size_t j = i + 1; j < s.size(); ++j) {
            if (s[i].size() != s[j].size()) return 3;
            int d = 0;
            for (size_t k = 0; k < s[i].size(); ++k) {
                d += s[i][k] != s[j][k];
                if (d > best) break;
            }
            if (d < best || (d == best && (i < bi || (i == bi && j < bj)))) {
                best = d;
                bi = i;
                bj = j;
            }
        }
    }
    if (best == INT_MAX) return 4;
    std::cout << bi << ',' << bj << ',' << best;
    return 0;
}
'''
    path = "/tmp/min_oracle.cpp"
    with open(path, "w") as f:
        f.write(source)
    subprocess.run(
        ["g++", "-O3", "-std=c++17", path, "-o", "/tmp/min_oracle"],
        check=True,
        timeout=60,
    )


def oracle(dataset):
    return subprocess.run(
        ["/tmp/min_oracle", dataset],
        check=True,
        capture_output=True,
        text=True,
        timeout=180,
    ).stdout.strip()


def run_submission():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=180)
    assert os.path.isfile(RESULT), "Running the release binary did not create result.txt"
    with open(RESULT, "r") as f:
        value = f.read().strip()
    assert re.fullmatch(r"\d+,\d+,\d+", value), f"Invalid result format: {value!r}"
    return value


def make_control_dataset():
    rng = random.Random(8675309)
    bases = "ACGT"
    seqs = ["".join(rng.choice(bases) for _ in range(50)) for _ in range(10000)]
    for first, second, pos in ((7, 900, 11), (12, 800, 23)):
        changed = list(seqs[first])
        changed[pos] = bases[(bases.index(changed[pos]) + 1) % 4]
        seqs[second] = "".join(changed)
    return seqs


def test_release_program_parallel_and_correct():
    main_rs = os.path.join(PROJECT, "src", "main.rs")
    with open(main_rs, "r") as f:
        source = f.read()
    parallel_api = re.compile(
        r"(?:\.\s*(?:par_iter|par_iter_mut|into_par_iter|into_par_iter_mut|par_bridge)\s*\(|"
        r"rayon\s*::\s*(?:join|scope|scope_fifo)\s*\(|"
        r"\.\s*(?:install|spawn|spawn_fifo)\s*\()"
    )
    assert parallel_api.search(source), "main.rs does not use a Rayon parallel execution API"

    subprocess.run(
        [CARGO, "build", "--release", "--bin", "seq_match"],
        cwd=PROJECT,
        check=True,
        timeout=240,
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Release binary is missing"
    compile_oracle()

    with open(DATASET, "rb") as f:
        original = f.read()

    try:
        controlled = make_control_dataset()
        with open(DATASET, "w") as f:
            f.write("\n".join(controlled) + "\n")
        expected_control = oracle(DATASET)
        actual_control = run_submission()
        assert actual_control == expected_control, (
            f"Controlled dataset: expected {expected_control}, got {actual_control}"
        )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original)

    expected_original = oracle(DATASET)
    assert expected_original == "42,1337,2", (
        f"Independent computation produced unexpected original answer {expected_original}"
    )
    actual_original = run_submission()
    assert actual_original == expected_original, (
        f"Original dataset: expected {expected_original}, got {actual_original}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
