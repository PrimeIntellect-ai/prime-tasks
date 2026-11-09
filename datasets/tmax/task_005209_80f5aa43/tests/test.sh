#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import subprocess
import pytest


def test_rust_project_exists():
    """Verify that the Rust project directory and Cargo.toml exist."""
    cargo_toml = "/home/user/minimizer/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"Rust project file {cargo_toml} is missing."


def test_minimized_files_content():
    """Verify that the minimized files exist and contain the correct UTF-8 text."""
    expected_contents = {
        "part1.gcode.gz": "G28\nG1 X10 Y10\nM104 S0\n",
        "part2.gcode.gz": "G90\nM82\nG1 Z0.2 F3000\n",
        "part3.gcode.gz": ""
    }

    for filename, expected in expected_contents.items():
        path = f"/home/user/minimized_gcode/{filename}"
        assert os.path.isfile(path), f"Minimized file {path} is missing."

        try:
            with gzip.open(path, 'rt', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            pytest.fail(f"Failed to read {path} as a gzipped UTF-8 file: {e}")

        assert content == expected, f"Content mismatch in {filename}. Expected {repr(expected)}, got {repr(content)}"


def test_manifest_exists_and_correct():
    """Verify that the manifest.txt exists and matches the actual sha256 checksums."""
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    minimized_dir = "/home/user/minimized_gcode"
    try:
        result = subprocess.run(
            ["sha256sum", "part1.gcode.gz", "part2.gcode.gz", "part3.gcode.gz"],
            cwd=minimized_dir,
            capture_output=True,
            text=True,
            check=True
        )
        actual_manifest_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run sha256sum in {minimized_dir}: {e}")

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest_content = f.read().strip()
    manifest_lines = [line.strip() for line in manifest_content.split('\n') if line.strip()]

    for expected_line in actual_manifest_lines:
        assert expected_line in manifest_lines, (
            f"Missing or incorrect manifest entry. "
            f"Expected to find '{expected_line}' in {manifest_path}."
        )


def minimize_reference(text):
    output = []
    for line in text.splitlines():
        line = line.split(';', 1)[0].rstrip(' \t')
        if line:
            output.append(line + '\n')
    return ''.join(output)


def test_rust_utility_processes_unseen_inputs():
    """Build and execute the Rust utility on unpredictable UTF-16LE gzip inputs."""
    token = secrets.token_hex(10)
    x = secrets.randbelow(9000) + 1000
    y = secrets.randbelow(9000) + 1000
    inputs = {
        f"audit_{token}.gcode.gz": (
            f"; generated audit comment {token}\n"
            f"  G1 X{x} Y{y}\t  ; remove this {token}\n"
            " \t   \n"
            f"M117 café 雪 {token};inline comment\n"
            "G4 P0\t \t\n"
        ),
        f"audit_comments_{token}.gcode.gz": (
            f"; comment only {token}\n"
            "; another comment\n"
            "\t ; whitespace and comment\n"
        )
    }

    source_dir = "/home/user/bloated_gcode"
    output_dir = "/home/user/minimized_gcode"
    for filename, text in inputs.items():
        with gzip.open(os.path.join(source_dir, filename), "wb") as f:
            f.write(text.encode("utf-16le"))
        # A valid run must replace this deliberately invalid output.
        with open(os.path.join(output_dir, filename), "wb") as f:
            f.write(b"not a gzip stream")

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "cargo", "run", "--quiet", "--manifest-path", "/home/user/minimizer/Cargo.toml"],
        cwd="/home/user/minimizer",
        capture_output=True,
        text=True,
        timeout=180
    )
    assert result.returncode == 0, (
        "The Rust utility failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    for filename, source_text in inputs.items():
        output_path = os.path.join(output_dir, filename)
        assert os.path.isfile(output_path), f"Utility did not create {output_path}"
        try:
            with gzip.open(output_path, "rb") as f:
                raw = f.read()
            actual = raw.decode("utf-8")
        except Exception as e:
            pytest.fail(f"Utility output {output_path} is not valid gzip-compressed UTF-8: {e}")
        expected = minimize_reference(source_text)
        assert actual == expected, (
            f"Utility produced incorrect content for unseen input {filename}. "
            f"Expected {expected!r}, got {actual!r}"
        )

    # Re-check that executing the utility correctly processes the supplied inputs too.
    expected_originals = {
        "part1.gcode.gz": "G28\nG1 X10 Y10\nM104 S0\n",
        "part2.gcode.gz": "G90\nM82\nG1 Z0.2 F3000\n",
        "part3.gcode.gz": ""
    }
    for filename, expected in expected_originals.items():
        with gzip.open(os.path.join(output_dir, filename), "rt", encoding="utf-8") as f:
            assert f.read() == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
