#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import subprocess
import tempfile
from collections import Counter

INPUT_FILE = "/home/user/primers.fa"
OUTPUT_FILE = "/home/user/jsd_result.txt"


def get_kmers(seq, k=3):
    return [seq[i:i+k] for i in range(len(seq)-k+1)]


def kl_div(X, Y):
    return sum(x * math.log(x / y) for x, y in zip(X, Y))


def expected_for_sequences(seqA, seqB):
    kmersA = get_kmers(seqA)
    kmersB = get_kmers(seqB)
    countA = Counter(kmersA)
    countB = Counter(kmersB)
    bases = ['A', 'C', 'G', 'T']
    all_kmers = [a+b+c for a in bases for b in bases for c in bases]
    totalA = len(kmersA) + 64
    totalB = len(kmersB) + 64
    P = [(countA.get(kmer, 0) + 1) / totalA for kmer in all_kmers]
    Q = [(countB.get(kmer, 0) + 1) / totalB for kmer in all_kmers]
    M = [(p + q) / 2.0 for p, q in zip(P, Q)]
    jsd = 0.5 * kl_div(P, M) + 0.5 * kl_div(Q, M)
    return f"{jsd:.6f}"


def read_sequences(file_path):
    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.startswith(">")]
    assert len(lines) == 2, "Expected exactly two sequence lines in primers.fa"
    return lines[0], lines[1]


def compute_expected_jsd(file_path):
    return expected_for_sequences(*read_sequences(file_path))


def source_paths():
    manifests = []
    rust_sources = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"target", ".rustup", ".cargo", ".git"}]
        if "Cargo.toml" in files:
            manifests.append(os.path.join(root, "Cargo.toml"))
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(os.path.join(root, name))
    return manifests, rust_sources


def discover_candidates(tmpdir):
    manifests, rust_sources = source_paths()
    assert rust_sources, "No Rust source file was created under /home/user"
    candidates = []
    seen = set()

    for manifest in manifests:
        try:
            result = subprocess.run(
                ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
                cwd=os.path.dirname(manifest), text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=30, check=True
            )
            metadata = json.loads(result.stdout)
        except Exception:
            continue
        for package in metadata.get("packages", []):
            for target in package.get("targets", []):
                if "bin" not in target.get("kind", []):
                    continue
                key = (package.get("name"), target.get("name"), package.get("manifest_path"))
                if key in seen:
                    continue
                seen.add(key)
                package_manifest = package["manifest_path"]
                build = ["cargo", "build", "--quiet", "--manifest-path", package_manifest,
                         "--package", package["name"], "--bin", target["name"]]
                run = ["cargo", "run", "--quiet", "--manifest-path", package_manifest,
                       "--package", package["name"], "--bin", target["name"]]
                candidates.append((f"Cargo binary {package['name']}:{target['name']}",
                                   os.path.dirname(package_manifest), build, run))

    for index, source in enumerate(rust_sources):
        try:
            with open(source, "r", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        if not re.search(r"\bfn\s+main\s*\(", text):
            continue
        executable = os.path.join(tmpdir, f"rust_candidate_{index}")
        build = ["rustc", "--crate-name", f"verifier_candidate_{index}", source, "-o", executable]
        candidates.append((f"Rust source {source}", os.path.dirname(source), build, [executable]))

    assert candidates, "No executable Rust binary target or Rust source containing fn main was found"
    return candidates


def write_fixture(seq_a, seq_b):
    with open(INPUT_FILE, "w") as f:
        f.write(f">Primer_A\n{seq_a}\n>Primer_B\n{seq_b}\n")


def random_sequence(length):
    alphabet = "ACGT"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_jsd_result_and_rust_execution():
    assert os.path.exists(INPUT_FILE), f"Input file {INPUT_FILE} does not exist."
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    # Preserve the original exact comparison.
    expected_jsd_str = compute_expected_jsd(INPUT_FILE)
    with open(OUTPUT_FILE, "r") as f:
        actual_jsd_str = f.read().strip()
    assert actual_jsd_str == expected_jsd_str, (
        f"Expected JSD value '{expected_jsd_str}', but got '{actual_jsd_str}' in {OUTPUT_FILE}."
    )

    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()
    with open(OUTPUT_FILE, "rb") as f:
        original_output = f.read()
    original_sequences = read_sequences(INPUT_FILE)

    dynamic_cases = [original_sequences]
    for _ in range(3):
        a = random_sequence(19 + secrets.randbelow(25))
        b = random_sequence(19 + secrets.randbelow(25))
        dynamic_cases.append((a, b))

    failures = []
    try:
        with tempfile.TemporaryDirectory(prefix="rust_jsd_verify_") as tmpdir:
            candidates = discover_candidates(tmpdir)
            for label, cwd, build_command, run_command in candidates:
                try:
                    subprocess.run(build_command, cwd=cwd, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, timeout=90, check=True)
                    passed = True
                    for seq_a, seq_b in dynamic_cases:
                        write_fixture(seq_a, seq_b)
                        if os.path.exists(OUTPUT_FILE):
                            os.remove(OUTPUT_FILE)
                        subprocess.run(run_command, cwd=cwd, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, timeout=30, check=True)
                        if not os.path.isfile(OUTPUT_FILE):
                            passed = False
                            break
                        with open(OUTPUT_FILE, "r") as f:
                            actual = f.read().strip()
                        if actual != expected_for_sequences(seq_a, seq_b):
                            passed = False
                            break
                    if passed:
                        return
                    failures.append(f"{label}: produced an incorrect or missing result")
                except (subprocess.SubprocessError, OSError) as exc:
                    failures.append(f"{label}: did not compile/run successfully ({exc})")
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        with open(OUTPUT_FILE, "wb") as f:
            f.write(original_output)

    raise AssertionError("No compiled Rust program passed execution tests. " + "; ".join(failures[-5:]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
