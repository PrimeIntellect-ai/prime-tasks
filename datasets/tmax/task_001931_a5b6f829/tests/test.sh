#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

DETECTOR_PATH = Path("/home/user/detector")
PROJECT_PATH = Path("/home/user/detector_project")
ZIP_PATH = "/app/corpus.zip"
PASSWORD = "b1s3ct_s3cr3t!"


def run_detector(executable, sample):
    try:
        return subprocess.run(
            [str(executable), str(sample)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {sample.name}")


def assert_elf_executable(path):
    assert path.exists(), f"Detector binary not found at {path}"
    assert path.is_file(), f"{path} is not a file"
    st = path.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable"
    with path.open("rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"


def test_detector_exists_and_executable():
    assert_elf_executable(DETECTOR_PATH)


def test_detector_against_corpus():
    if not DETECTOR_PATH.exists():
        pytest.fail("Detector binary is missing.")

    with tempfile.TemporaryDirectory() as tmpdir:
        res = subprocess.run(
            ["unzip", "-P", PASSWORD, ZIP_PATH, "-d", tmpdir],
            capture_output=True,
            text=True,
        )
        assert res.returncode == 0, f"Failed to unzip corpus for testing: {res.stderr}"

        clean_dir = os.path.join(tmpdir, "clean")
        evil_dir = os.path.join(tmpdir, "evil")
        if not os.path.exists(clean_dir) and os.path.exists(os.path.join(tmpdir, "corpus", "clean")):
            clean_dir = os.path.join(tmpdir, "corpus", "clean")
            evil_dir = os.path.join(tmpdir, "corpus", "evil")

        assert os.path.exists(clean_dir), "Clean corpus directory not found in zip"
        assert os.path.exists(evil_dir), "Evil corpus directory not found in zip"

        clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
        evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

        assert len(clean_files) > 0, "No clean files found to test"
        assert len(evil_files) > 0, "No evil files found to test"

        clean_failed = []
        for cf in clean_files:
            if run_detector(DETECTOR_PATH, Path(cf)) != 0:
                clean_failed.append(os.path.basename(cf))

        evil_failed = []
        for ef in evil_files:
            if run_detector(DETECTOR_PATH, Path(ef)) == 0:
                evil_failed.append(os.path.basename(ef))

        errors = []
        if evil_failed:
            errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
        if clean_failed:
            errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
        if errors:
            pytest.fail(" | ".join(errors))


def build_rust_detector(target_dir):
    assert PROJECT_PATH.is_dir(), f"Rust project not found at {PROJECT_PATH}"
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "Cargo.toml is missing"
    assert any(PROJECT_PATH.rglob("*.rs")), "Rust project contains no .rs source files"

    env = os.environ.copy()
    env.pop("RUSTC_WRAPPER", None)
    env.pop("RUSTC_WORKSPACE_WRAPPER", None)
    env["CARGO_TARGET_DIR"] = str(target_dir)

    meta = subprocess.run(
        ["cargo", "metadata", "--offline", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_PATH,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert meta.returncode == 0, f"Invalid Rust/Cargo project: {meta.stderr}"
    metadata = json.loads(meta.stdout)
    bins = [t for p in metadata["packages"] for t in p["targets"] if "bin" in t["kind"]]
    assert bins, "Cargo project has no Rust binary target"

    preferred = [t for t in bins if t["name"] == "detector"]
    targets = preferred or bins
    built = []
    for target in targets:
        res = subprocess.run(
            ["cargo", "build", "--offline", "--release", "--bin", target["name"]],
            cwd=PROJECT_PATH,
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert res.returncode == 0, f"Rust detector project does not build: {res.stderr}"
        binary = Path(target_dir) / "release" / target["name"]
        assert_elf_executable(binary)
        built.append(binary)
    return built


def make_random_cases(root):
    cases = []

    def add(typ, embedded_name, should_reject):
        raw_name = embedded_name.encode("ascii")
        assert len(raw_name) < 256
        sample = root / (secrets.token_hex(12) + ".dat")
        sample.write_bytes(bytes([typ, len(raw_name)]) + raw_name)
        cases.append((sample, should_reject))

    # Isolate each part of the vulnerable predicate, rather than merely replaying
    # files whose directory names reveal their expected classification.
    for _ in range(8):
        token = secrets.token_hex(8)
        add(1, f"asset_{token}.bin", False)
        add(3, f"nested/{token}.dat", False)
        add(2, f"asset_{token}.bin", True)
        add(1, f"../private/{token}", True)
        add(1, f"dir/../../private/{token}", True)
    return cases


def test_content_based_detection_and_rust_source():
    with tempfile.TemporaryDirectory(prefix="samples_") as sample_tmp, tempfile.TemporaryDirectory(prefix="cargo_target_") as target_tmp:
        sample_root = Path(sample_tmp) / secrets.token_hex(10)
        sample_root.mkdir()
        cases = make_random_cases(sample_root)
        rebuilt_candidates = build_rust_detector(Path(target_tmp))

        executables = [DETECTOR_PATH]
        # At least one binary built directly from the submitted Rust project must
        # implement the same required validator behavior.
        rust_candidate_passed = False
        for candidate in rebuilt_candidates:
            if all((run_detector(candidate, path) != 0) == reject for path, reject in cases):
                rust_candidate_passed = True
                break
        assert rust_candidate_passed, "No binary built from the submitted Rust project implements the detector"

        failures = []
        for path, reject in cases:
            rc = run_detector(DETECTOR_PATH, path)
            if (rc != 0) != reject:
                failures.append(path.name)
        assert not failures, f"Installed detector misclassified randomized content-only cases: {', '.join(failures)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
