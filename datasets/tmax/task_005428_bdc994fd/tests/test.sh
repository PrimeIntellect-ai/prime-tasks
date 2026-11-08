#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import struct
import subprocess
import uuid
from pathlib import Path

import pytest

HOME = Path("/home/user")
ARCHIVE = HOME / "dataset.bak"
EXTRACTED = HOME / "extracted"
LOG = HOME / "malicious.log"
TOTAL = HOME / "extrusion_total.txt"
PAYLOADS = [b"echo 'hacked'", b"root::18704:0:99999:7:::"]


def prepare_runner():
    manifests = []
    rust_sources = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {"target", ".git", "extracted"}]
        root_path = Path(root)
        if "Cargo.toml" in files:
            manifests.append(root_path / "Cargo.toml")
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(root_path / name)

    assert rust_sources, "No Rust source file was found under /home/user"

    if manifests:
        manifest = sorted(manifests, key=lambda p: (len(p.parts), str(p)))[0]
        project_sources = [p for p in rust_sources if manifest.parent == p.parent or manifest.parent in p.parents]
        assert project_sources, f"Cargo project {manifest} contains no Rust source"
        build = subprocess.run(
            ["cargo", "build", "--release", "--manifest-path", str(manifest)],
            cwd=str(manifest.parent), capture_output=True, text=True, timeout=120
        )
        assert build.returncode == 0, f"Rust project did not compile:\n{build.stdout}\n{build.stderr}"

        def run():
            result = subprocess.run(
                ["cargo", "run", "--quiet", "--release", "--manifest-path", str(manifest)],
                cwd=str(manifest.parent), capture_output=True, text=True, timeout=60
            )
            assert result.returncode == 0, f"Rust program failed:\n{result.stdout}\n{result.stderr}"
        return run

    ordered = sorted(rust_sources, key=lambda p: (p.name != "main.rs", len(p.parts), str(p)))
    diagnostics = []
    binary = Path("/tmp/submission_rust_program")
    selected = None
    for source in ordered:
        result = subprocess.run(
            ["rustc", "--edition=2021", str(source), "-o", str(binary)],
            cwd=str(source.parent), capture_output=True, text=True, timeout=120
        )
        if result.returncode == 0:
            selected = source
            break
        diagnostics.append(f"{source}:\n{result.stderr}")
    assert selected is not None, "No Rust source compiled successfully:\n" + "\n".join(diagnostics)

    def run():
        result = subprocess.run(
            [str(binary)], cwd=str(selected.parent), capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, f"Rust program failed:\n{result.stdout}\n{result.stderr}"
    return run


def reset_outputs():
    if EXTRACTED.is_symlink():
        pytest.fail(f"Extraction directory must not be a symlink: {EXTRACTED}")
    if EXTRACTED.exists():
        shutil.rmtree(EXTRACTED)
    for path in (LOG, TOTAL):
        if path.exists() or path.is_symlink():
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()


def assert_original_payloads_absent():
    paths = [
        EXTRACTED / "../malicious_script.sh",
        EXTRACTED / "etc/fake_shadow",
        HOME / "malicious_script.sh",
        Path("/etc/fake_shadow"),
    ]
    for path in paths:
        if path.is_file():
            content = path.read_bytes()
            assert content not in PAYLOADS, f"Malicious file was extracted to: {path}"


def parse_archive(data):
    assert data[:8] == b"DATASET\0", "Invalid test archive magic"
    pos = 8
    entries = []
    while pos < len(data):
        assert pos + 2 <= len(data), "Truncated path length"
        path_len = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        assert pos + path_len + 4 <= len(data), "Truncated archive entry"
        path = data[pos:pos + path_len].decode("utf-8")
        pos += path_len
        size = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        assert pos + size <= len(data), "Truncated archive content"
        content = data[pos:pos + size]
        pos += size
        entries.append((path, content))
    return entries


def expected_from_archive(data):
    safe = {}
    malicious = []
    total = 0.0
    extrusion = re.compile(r"E([-+]?(?:\d+(?:\.\d*)?|\.\d+))")
    for path, content in parse_archive(data):
        if path.startswith("/") or "../" in path:
            malicious.append(path)
            continue
        safe[path] = content
        if path.endswith(".gcode"):
            for raw_line in content.decode("utf-8").splitlines():
                if raw_line.startswith("G1 "):
                    match = extrusion.search(raw_line)
                    if match:
                        total += float(match.group(1))
    return safe, malicious, total


def write_archive(entries):
    result = bytearray(b"DATASET\0")
    for path, content in entries:
        encoded = path.encode("utf-8")
        result += struct.pack("<H", len(encoded))
        result += encoded
        result += struct.pack("<I", len(content))
        result += content
    return bytes(result)


@pytest.fixture(scope="session", autouse=True)
def execute_rust_program():
    assert ARCHIVE.is_file(), f"Missing archive: {ARCHIVE}"
    assert_original_payloads_absent()
    runner = prepare_runner()
    reset_outputs()
    runner()
    return runner


def test_malicious_log():
    """Verify that malicious paths were correctly logged to malicious.log."""
    assert LOG.exists(), f"Missing file: {LOG}"
    with LOG.open("r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_lines = ["../malicious_script.sh", "/etc/fake_shadow"]
    assert set(lines) == set(expected_lines), f"Contents of {LOG} do not match expected. Got: {lines}"


def test_extrusion_total():
    """Verify that the total extrusion calculation is correct."""
    assert TOTAL.exists(), f"Missing file: {TOTAL}"
    content = TOTAL.read_text().strip()
    try:
        total = float(content)
    except ValueError:
        pytest.fail(f"Could not parse extrusion total as a float. Got: {content}")
    assert abs(total - 4.75) < 1e-6, f"Extrusion total is incorrect. Expected 4.75, got {total}"


def test_extracted_files():
    """Verify that safe files were correctly extracted to the extracted directory."""
    assert EXTRACTED.exists(), f"Missing directory: {EXTRACTED}"
    assert EXTRACTED.is_dir(), f"Not a directory: {EXTRACTED}"
    expected_files = {
        "normal1.gcode": b"G1 X10 Y10 E2.5\nG1 X20 E1.5\nM104 S200\n",
        "nested/dir/safe.gcode": b"G28\nG1 Z1.0 E0.5\nG1 X0 Y0 E0.25\n",
        "metadata.txt": b"Experiment 42 - Standard PLA",
    }
    for rel_path, expected_content in expected_files.items():
        abs_path = EXTRACTED / rel_path
        assert abs_path.exists(), f"Missing extracted file: {abs_path}"
        assert abs_path.is_file(), f"Not a file: {abs_path}"
        assert abs_path.read_bytes() == expected_content, f"Content mismatch for {abs_path}."


def test_malicious_files_not_extracted():
    """Verify that malicious files were NOT extracted."""
    assert_original_payloads_absent()


def test_z_dynamic_archive(execute_rust_program):
    """Run the compiled Rust artifact on an unpredictable archive and derive all expected results from it."""
    runner = execute_rust_program
    token = uuid.uuid4().hex
    escape = HOME / f"escape_{token}.txt"
    absolute = HOME / f"absolute_{token}.txt"
    rejected_inside = EXTRACTED / f"rejected_{token}.txt"
    entries = [
        (f"prints/{token}/a.gcode", b"G1 X1 E1.125\nG1 Y2 E-0.25\nG0 E99\n"),
        (f"prints/{token}/b.gcode", b"G28\nG1 Z2 E3.375\nG1 X4\n"),
        (f"notes/{token}.txt", b"dynamic metadata"),
        (f"../escape_{token}.txt", b"dynamic traversal payload"),
        (str(absolute), b"dynamic absolute payload"),
        (f"nested/../rejected_{token}.txt", b"must be rejected by literal traversal check"),
    ]
    archive_data = write_archive(entries)
    expected_safe, expected_malicious, expected_total = expected_from_archive(archive_data)
    original_data = ARCHIVE.read_bytes()
    try:
        for path in (escape, absolute, rejected_inside):
            if path.exists() or path.is_symlink():
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                else:
                    path.unlink()
        ARCHIVE.write_bytes(archive_data)
        reset_outputs()
        runner()

        assert EXTRACTED.is_dir(), "Rust program did not create the extraction directory"
        for rel_path, expected_content in expected_safe.items():
            output = EXTRACTED / rel_path
            assert output.is_file(), f"Missing dynamically expected extracted file: {output}"
            assert output.read_bytes() == expected_content, f"Incorrect dynamic content for {output}"

        assert LOG.is_file(), "Rust program did not create malicious.log for the dynamic archive"
        logged = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
        assert logged == expected_malicious, f"Dynamic malicious paths were logged incorrectly: {logged}"

        assert TOTAL.is_file(), "Rust program did not create extrusion_total.txt for the dynamic archive"
        try:
            actual_total = float(TOTAL.read_text().strip())
        except ValueError:
            pytest.fail("Dynamic extrusion total is not a floating-point number")
        assert abs(actual_total - expected_total) < 1e-6, (
            f"Dynamic extrusion total is incorrect: expected {expected_total}, got {actual_total}"
        )

        for path in (escape, absolute, rejected_inside):
            assert not path.exists(), f"Malicious dynamic entry was extracted to: {path}"
    finally:
        ARCHIVE.write_bytes(original_data)
        for path in (escape, absolute, rejected_inside):
            if path.exists() or path.is_symlink():
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                else:
                    path.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
