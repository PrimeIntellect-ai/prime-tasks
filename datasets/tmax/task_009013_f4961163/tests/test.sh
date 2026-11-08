#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pathlib
import re
import subprocess

PROJECT = pathlib.Path("/home/user/risk_engine")
TX_FILE = pathlib.Path("/home/user/extracted_tx.txt")
SCORE_FILE = pathlib.Path("/home/user/final_score.txt")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=180, **kwargs)


def extracted_from_dump():
    dump = PROJECT / "crash.dump"
    assert dump.is_file(), f"Memory dump {dump} is missing."
    matches = re.findall(rb"TXID-[0-9]{5}-[A-Z]+", dump.read_bytes())
    assert matches, "No transaction ID was found in crash.dump."
    unique = set(matches)
    assert len(unique) == 1, f"Ambiguous transaction IDs in crash.dump: {unique}"
    return matches[0].decode("ascii")


def test_extracted_tx_file():
    path = "/home/user/extracted_tx.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you extract the transaction ID?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "TXID-84729-OMEGA", f"Extracted TXID is incorrect. Found: '{content}'"
    assert content == extracted_from_dump(), "extracted_tx.txt does not contain the ID present in crash.dump."


def test_dependency_conflict_is_repaired_in_manifests():
    root_manifest = PROJECT / "Cargo.toml"
    math_manifest = PROJECT / "libs/math_utils/Cargo.toml"
    assert root_manifest.is_file(), f"Missing manifest: {root_manifest}"
    assert math_manifest.is_file(), f"Missing manifest: {math_manifest}"

    result = run(["cargo", "metadata", "--format-version", "1"], cwd=PROJECT)
    assert result.returncode == 0, f"cargo metadata failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    packages = {p["id"]: p for p in metadata["packages"]}
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    root_id = metadata["resolve"]["root"]
    assert root_id in packages and packages[root_id]["name"] == "risk_engine", "The root risk_engine package is missing."

    def dependency_package(node_id, package_name):
        found = []
        for dep in nodes[node_id].get("deps", []):
            pkg = packages.get(dep["pkg"])
            if pkg and pkg["name"] == package_name:
                found.append(dep["pkg"])
        assert len(found) == 1, f"Package {packages[node_id]['name']} must have exactly one resolved {package_name} dependency."
        return found[0]

    root_common = dependency_package(root_id, "common_types")
    math_id = dependency_package(root_id, "math_utils")
    math_common = dependency_package(math_id, "common_types")
    assert pathlib.Path(packages[math_id]["manifest_path"]).resolve() == math_manifest.resolve(), "risk_engine is not using the supplied local math_utils crate."
    assert root_common == math_common, (
        "risk_engine and math_utils still resolve to different common_types packages; "
        "repair their Cargo.toml dependencies so both use the same crate."
    )


def test_cargo_test_passes_and_f64_implementation_is_general():
    project_dir = "/home/user/risk_engine"
    assert os.path.exists(project_dir), f"Project directory {project_dir} is missing."
    source = PROJECT / "src/main.rs"
    assert source.is_file() and not source.is_symlink(), f"Expected a regular Rust source file at {source}."

    original = source.read_bytes()
    hidden_tests = r'''

#[cfg(test)]
mod verifier_generated_precision_tests_91d3 {
    use super::calculate_risk_score;

    fn reference(mut value: f64, iterations: u32) -> f64 {
        for _ in 0..iterations {
            value *= 1.01_f64;
        }
        value
    }

    #[test]
    fn checks_f64_precision_for_unseen_inputs() {
        let fixed = [
            (0.1_f64, 17_u32),
            (42.125_f64, 91_u32),
            (1234.567890123_f64, 237_u32),
            (9_876_543.210987_f64, 411_u32),
        ];
        for (base, iterations) in fixed {
            let got: f64 = calculate_risk_score(base, iterations);
            let expected = reference(base, iterations);
            assert_eq!(got.to_bits(), expected.to_bits(),
                "wrong f64 compounding result for base={base}, iterations={iterations}: got {got}, expected {expected}");
        }

        let mut state: u64 = 0x6a09e667f3bcc909;
        for _ in 0..24 {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let base = ((state >> 17) % 4_000_000_000) as f64 / 1000.0 + 0.125;
            let iterations = ((state >> 48) % 499 + 1) as u32;
            let got: f64 = calculate_risk_score(base, iterations);
            let expected = reference(base, iterations);
            assert_eq!(got.to_bits(), expected.to_bits(),
                "calculate_risk_score is not performing the required f64 iterative calculation");
        }
    }
}
'''.encode()

    try:
        source.write_bytes(original + hidden_tests)
        result = run(["cargo", "test"], cwd=project_dir)
    finally:
        source.write_bytes(original)

    assert result.returncode == 0, f"cargo test failed. Compilation or precision error not resolved.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_binary_execution_and_final_score_file():
    tx_id = TX_FILE.read_text().strip()
    assert tx_id == extracted_from_dump()
    result = run(["cargo", "run", "--quiet", "--", tx_id], cwd=PROJECT)
    assert result.returncode == 0, f"cargo run failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    output = result.stdout.strip()
    assert len(output.splitlines()) == 1, f"Program must output only the numeric score, got: {output!r}"
    try:
        program_score = float(output)
    except ValueError:
        assert False, f"Program output is not a valid numeric score: {output!r}"

    expected = 1000.0
    for _ in range(365):
        expected *= 1.01
    assert math.isfinite(program_score) and abs(program_score - expected) < 1e-10, (
        f"Executed program produced an incorrect f64 risk score: expected {expected!r}, got {output!r}"
    )

    path = "/home/user/final_score.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you run the program and save the output?"
    with open(path, "r") as f:
        content = f.read().strip()

    expected_score = "37783.43433288728"
    try:
        score_val = float(content)
        expected_val = float(expected_score)
        assert abs(score_val - expected_val) < 1e-5, f"Final score in {path} is incorrect. Expected approx {expected_score}, got {content}"
    except ValueError:
        assert False, f"Content of {path} is not a valid float: '{content}'"

    assert content == output, (
        f"final_score.txt does not contain the exact score emitted by the repaired binary. "
        f"File: {content!r}; program: {output!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
