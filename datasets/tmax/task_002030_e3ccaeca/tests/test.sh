#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import shutil
import subprocess

DOCS_DIR = "/home/user/docs_draft"
INDEXER_DIR = "/home/user/indexer"


def test_markdown_transformed():
    """Verify that the configured sed substitutions were applied faithfully."""
    expected = {
        "intro.md": (
            "# Introduction to the System\n"
            "This is a [] document.\n"
            "NOE: dd architecture diagram\n"
        ),
        "setup.md": (
            "# Installation Guide\n"
            "ollow these steps to install the system.\n"
            "NOE: Verify permissions on step 3\n"
        ),
        "api.md": (
            "# PI eference\n"
            "[] PI Endpoints:\n"
            "NOE: ocument the /users endpoint\n"
        ),
    }

    for filename, expected_content in expected.items():
        path = os.path.join(DOCS_DIR, filename)
        assert os.path.isfile(path), f"{path} is missing"
        with open(path, "r") as f:
            content = f.read()
        assert content == expected_content, f"{filename} does not reflect the configured sed commands"
        assert "[DRAFT]" not in content, f"{filename} still contains [DRAFT]"


def test_index_txt():
    """Verify that index.txt contains the transformed titles for all markdown files."""
    index_path = os.path.join(DOCS_DIR, "index.txt")
    assert os.path.isfile(index_path), f"{index_path} is missing"

    with open(index_path, "r") as f:
        lines = sorted(line.strip() for line in f if line.strip())

    expected = [
        "api.md: # PI eference",
        "intro.md: # Introduction to the System",
        "setup.md: # Installation Guide",
    ]
    assert lines == expected, f"index.txt content does not match expected. Found: {lines}"


def test_manifest_sha256():
    """Verify that manifest.sha256 contains valid sha256sum-format entries."""
    manifest_path = os.path.join(DOCS_DIR, "manifest.sha256")
    assert os.path.isfile(manifest_path), f"{manifest_path} is missing"

    with open(manifest_path, "r") as f:
        manifest_lines = [line.rstrip("\n") for line in f if line.strip()]

    manifest_hashes = {}
    for line in manifest_lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", line)
        assert match, f"Invalid sha256sum-format manifest line: {line!r}"
        digest, filename = match.groups()
        assert filename not in manifest_hashes, f"Duplicate manifest entry: {filename}"
        manifest_hashes[filename] = digest

    expected_files = ["intro.md", "setup.md", "api.md", "index.txt"]
    for filename in expected_files:
        assert filename in manifest_hashes, f"{filename} is missing from manifest.sha256"
        filepath = os.path.join(DOCS_DIR, filename)
        assert os.path.isfile(filepath), f"{filepath} is missing"
        with open(filepath, "rb") as file_obj:
            actual_hash = hashlib.sha256(file_obj.read()).hexdigest()
        assert manifest_hashes[filename] == actual_hash, f"Hash mismatch in manifest for {filename}"


def test_rust_project_concurrency_and_locking():
    cargo_toml = os.path.join(INDEXER_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), "Rust project is missing Cargo.toml"

    rust_files = []
    for root, dirs, files in os.walk(INDEXER_DIR):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                rust_files.append(os.path.join(root, name))
    assert rust_files, "Rust project contains no .rs source files"

    with open(cargo_toml, "r") as f:
        cargo_text = f.read()
    source = "\n".join(open(path, "r").read() for path in rust_files)

    assert re.search(r"(?mi)^\s*(fs2|fs3)\s*=", cargo_text), "Cargo.toml must depend on fs2 or fs3"
    assert re.search(r"(?:std::)?thread::(?:spawn|scope)\b", source), "Rust source must create concurrent threads"
    assert re.search(r"\bspawn\s*\(", source), "Rust source does not spawn worker threads"
    assert re.search(r"\block_exclusive\s*\(", source), "Rust source does not acquire an exclusive file lock"
    assert re.search(r"\bunlock\s*\(", source), "Rust source does not explicitly release the file lock"


def test_rust_program_on_derived_inputs():
    """Compile and execute the submitted Rust project against unpredictable files."""
    token = secrets.token_hex(8)
    backup = f"{DOCS_DIR}.verifier-backup-{token}"
    assert not os.path.exists(backup)

    os.rename(DOCS_DIR, backup)
    os.mkdir(DOCS_DIR)
    try:
        expected_index = []
        expected_files = []
        for i in range(9):
            filename = f"generated_{token}_{i}.md"
            title = f"# Generated title {token} number {i}"
            content = f"preamble {i}\n{title}\n# Later title {i}\nbody {token}\n"
            with open(os.path.join(DOCS_DIR, filename), "w") as f:
                f.write(content)
            expected_files.append(filename)
            expected_index.append(f"{filename}: {title}")

        env = os.environ.copy()
        env["PATH"] = "/root/.cargo/bin:" + env.get("PATH", "")
        result = subprocess.run(
            ["/root/.cargo/bin/cargo", "run", "--quiet"],
            cwd=INDEXER_DIR,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, f"Rust program failed:\n{result.stdout}\n{result.stderr}"

        index_path = os.path.join(DOCS_DIR, "index.txt")
        assert os.path.isfile(index_path), "Executed Rust program did not create index.txt"
        with open(index_path, "r") as f:
            actual_index = sorted(line.strip() for line in f if line.strip())
        assert actual_index == sorted(expected_index), f"Rust program produced an incorrect dynamic index: {actual_index}"

        manifest_path = os.path.join(DOCS_DIR, "manifest.sha256")
        assert os.path.isfile(manifest_path), "Executed Rust program did not create manifest.sha256"
        parsed = {}
        with open(manifest_path, "r") as f:
            for raw_line in f:
                line = raw_line.rstrip("\n")
                if not line:
                    continue
                match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", line)
                assert match, f"Invalid dynamic manifest line: {line!r}"
                digest, filename = match.groups()
                assert filename not in parsed, f"Duplicate dynamic manifest entry: {filename}"
                parsed[filename] = digest

        expected_manifest_files = set(expected_files + ["index.txt"])
        assert set(parsed) == expected_manifest_files, f"Dynamic manifest has wrong files: {set(parsed)}"
        for filename in expected_manifest_files:
            with open(os.path.join(DOCS_DIR, filename), "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            assert parsed[filename] == digest, f"Dynamic manifest hash mismatch for {filename}"
    finally:
        shutil.rmtree(DOCS_DIR, ignore_errors=True)
        os.rename(backup, DOCS_DIR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
