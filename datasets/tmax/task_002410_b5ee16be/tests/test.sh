#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import struct
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/elf_inspector"


def read_elf_header(filepath):
    """Read e_machine and e_entry directly from the ELF header."""
    with open(filepath, "rb") as f:
        header = f.read(64)

    assert header[:4] == b"\x7fELF", f"{filepath} is not an ELF file"
    elf_class = header[4]
    data_encoding = header[5]
    assert elf_class in (1, 2), f"Unsupported ELF class in {filepath}"
    assert data_encoding in (1, 2), f"Unsupported ELF byte order in {filepath}"

    endian = "<" if data_encoding == 1 else ">"
    machine = struct.unpack_from(endian + "H", header, 18)[0]
    if elf_class == 1:
        entry = struct.unpack_from(endian + "I", header, 24)[0]
    else:
        entry = struct.unpack_from(endian + "Q", header, 24)[0]
    return machine, entry


def test_target_files_txt():
    """Check that target_files.txt contains the correct filenames extracted from the log."""
    target_files_path = "/home/user/target_files.txt"
    assert os.path.isfile(target_files_path), f"File {target_files_path} does not exist."

    with open(target_files_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {target_files_path}, found {len(lines)}."
    assert lines[0] == "sys_true", f"Expected first line to be 'sys_true', got '{lines[0]}'."
    assert lines[1] == "sys_false", f"Expected second line to be 'sys_false', got '{lines[1]}'."


def test_rust_project_exists():
    """Check that the Rust Cargo project was created and directly depends on goblin."""
    cargo_toml_path = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(cargo_toml_path), f"Rust project Cargo.toml not found at {cargo_toml_path}."

    with open(cargo_toml_path, "r") as f:
        content = f.read()
    assert "goblin" in content, "The 'goblin' crate is missing from Cargo.toml dependencies."

    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert result.returncode == 0, f"Cargo metadata failed:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    assert metadata.get("packages"), "Cargo project contains no package."
    assert any(
        dep.get("name") == "goblin"
        for package in metadata["packages"]
        for dep in package.get("dependencies", [])
    ), "The Cargo package must declare goblin as a dependency."


@pytest.fixture(scope="session")
def inspector_binary():
    result = subprocess.run(
        ["cargo", "build", "--quiet"], cwd=PROJECT,
        text=True, capture_output=True, timeout=180
    )
    assert result.returncode == 0, f"Rust CLI failed to build:\n{result.stderr}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT, text=True, capture_output=True, timeout=60
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    bin_names = [
        target["name"]
        for package in metadata["packages"]
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
    ]
    assert len(bin_names) == 1, f"Expected exactly one Rust binary target, found {bin_names}."
    binary = os.path.join(metadata["target_directory"], "debug", bin_names[0])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), f"Built CLI not found at {binary}."
    return binary


def run_inspector(binary, filepath):
    result = subprocess.run(
        [binary, filepath], text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"Inspector failed for {filepath}:\n{result.stderr}"
    lines = result.stdout.splitlines()
    assert len(lines) == 1 and lines[0].strip(), \
        f"Inspector must print exactly one JSON line; got {result.stdout!r}"
    try:
        value = json.loads(lines[0])
    except json.JSONDecodeError as e:
        pytest.fail(f"Inspector emitted invalid JSON for {filepath}: {e}")
    assert isinstance(value, dict), "Inspector output must be a JSON object."
    assert set(value) == {"file", "machine", "entry"}, \
        f"Inspector output has incorrect keys: {set(value)}"
    return value


def test_rust_cli_parses_elf_headers(inspector_binary):
    """Execute the submitted CLI on original and verifier-created ELF inputs."""
    inputs = [
        "/home/user/artifacts/sys_true",
        "/home/user/artifacts/sys_false",
        "/home/user/artifacts/sys_ls",
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        for index, (source, machine, entry) in enumerate([
            ("/home/user/artifacts/sys_true", 3, 0x12345678),
            ("/home/user/artifacts/sys_ls", 183, 0x23456789),
        ]):
            destination = os.path.join(tmpdir, f"probe_{index}.elf")
            shutil.copyfile(source, destination)
            with open(destination, "r+b") as f:
                ident = f.read(16)
                endian = "<" if ident[5] == 1 else ">"
                elf_class = ident[4]
                f.seek(18)
                f.write(struct.pack(endian + "H", machine))
                f.seek(24)
                f.write(struct.pack(endian + ("I" if elf_class == 1 else "Q"), entry))
            inputs.append(destination)

        for filepath in inputs:
            expected_machine, expected_entry = read_elf_header(filepath)
            value = run_inspector(inspector_binary, filepath)
            assert value["file"] == os.path.basename(filepath)
            assert type(value["machine"]) is int
            assert type(value["entry"]) is int
            assert value["machine"] == expected_machine, \
                f"Machine mismatch for {filepath}: expected {expected_machine}, got {value['machine']}"
            assert value["entry"] == expected_entry, \
                f"Entry mismatch for {filepath}: expected {expected_entry}, got {value['entry']}"


def get_elf_entry(filepath):
    """Helper to extract the entry point of an ELF file using readelf."""
    try:
        entry_out = subprocess.check_output(
            f"readelf -h {filepath} | grep 'Entry point address:'", shell=True
        ).decode()
        entry_hex = entry_out.split(":", 1)[1].strip()
        return int(entry_hex, 16)
    except Exception as e:
        pytest.fail(f"Failed to read ELF entry point for {filepath}: {e}")


def test_final_report_jsonl():
    """Check that final_report.jsonl contains the correct parsed ELF metadata."""
    report_path = "/home/user/final_report.jsonl"
    assert os.path.isfile(report_path), f"Final report file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 JSON lines in {report_path}, found {len(lines)}."

    try:
        data1 = json.loads(lines[0])
        data2 = json.loads(lines[1])
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON lines from report: {e}")

    expected_true_machine, direct_true_entry = read_elf_header("/home/user/artifacts/sys_true")
    expected_false_machine, direct_false_entry = read_elf_header("/home/user/artifacts/sys_false")
    expected_true_entry = get_elf_entry("/home/user/artifacts/sys_true")
    expected_false_entry = get_elf_entry("/home/user/artifacts/sys_false")
    assert direct_true_entry == expected_true_entry
    assert direct_false_entry == expected_false_entry

    assert "file" in data1, "Missing 'file' key in first JSON object."
    assert "machine" in data1, "Missing 'machine' key in first JSON object."
    assert "entry" in data1, "Missing 'entry' key in first JSON object."
    assert data1["file"] == "sys_true", f"First file must be 'sys_true', got '{data1['file']}'."
    assert isinstance(data1["machine"], int), "The 'machine' value must be an integer."
    assert data1["machine"] == expected_true_machine, \
        f"sys_true machine mismatch. Expected {expected_true_machine}, got {data1['machine']}."
    assert data1["entry"] == expected_true_entry, \
        f"sys_true entry point mismatch. Expected {expected_true_entry}, got {data1['entry']}."

    assert "file" in data2, "Missing 'file' key in second JSON object."
    assert "machine" in data2, "Missing 'machine' key in second JSON object."
    assert "entry" in data2, "Missing 'entry' key in second JSON object."
    assert data2["file"] == "sys_false", f"Second file must be 'sys_false', got '{data2['file']}'."
    assert isinstance(data2["machine"], int), "The 'machine' value must be an integer."
    assert data2["machine"] == expected_false_machine, \
        f"sys_false machine mismatch. Expected {expected_false_machine}, got {data2['machine']}."
    assert data2["entry"] == expected_false_entry, \
        f"sys_false entry point mismatch. Expected {expected_false_entry}, got {data2['entry']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
