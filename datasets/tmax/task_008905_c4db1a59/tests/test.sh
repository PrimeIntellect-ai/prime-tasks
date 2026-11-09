#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import stat
import subprocess
import tempfile
import uuid


def run_checked(command, timeout):
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        raise AssertionError(
            f"Command timed out after {timeout} seconds: {' '.join(command)}\n{output}"
        )
    assert process.returncode == 0, (
        f"Command failed with exit code {process.returncode}: "
        f"{' '.join(command)}\n{output}"
    )
    return output


def test_result_list_txt():
    result_file = "/home/user/result_list.txt"
    assert os.path.isfile(result_file), f"File {result_file} was not created."

    with open(result_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/processed_data/file1.utf8",
        "/home/user/processed_data/subset_A/file2.utf8"
    ]

    assert sorted(lines) == sorted(expected_lines), f"Contents of {result_file} do not match the expected output. Got: {lines}"


def test_converted_files_content():
    file1 = "/home/user/processed_data/file1.utf8"
    file2 = "/home/user/processed_data/subset_A/file2.utf8"

    assert os.path.isfile(file1), f"Converted file {file1} is missing."
    assert os.path.isfile(file2), f"Converted file {file2} is missing."

    with open(file1, "rb") as f:
        content1 = f.read()
    expected_content1 = bytes([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0xC3, 0xA9, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65])
    assert content1 == expected_content1, f"Content of {file1} is incorrect or not properly converted to UTF-8."

    with open(file2, "rb") as f:
        content2 = f.read()
    expected_content2 = bytes([0x44, 0x61, 0x74, 0x61, 0x20, 0xC3, 0xB1, 0x6F])
    assert content2 == expected_content2, f"Content of {file2} is incorrect or not properly converted to UTF-8."


def test_no_extra_files():
    processed_dir = "/home/user/processed_data"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} is missing."

    found_files = []
    for root, _, files in os.walk(processed_dir):
        for file in files:
            found_files.append(os.path.join(root, file))

    expected_files = [
        "/home/user/processed_data/file1.utf8",
        "/home/user/processed_data/subset_A/file2.utf8"
    ]

    assert len(found_files) == len(expected_files), f"Found unexpected files in {processed_dir}. Make sure symlink loops were avoided."


def test_rust_project_on_unseen_input_and_symlink_loop():
    project = "/home/user/dataset_normalizer"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isdir(project), f"Rust project directory {project} is missing."
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} is missing."

    rust_sources = []
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d != "target"]
        rust_sources.extend(
            os.path.join(root, name) for name in files if name.endswith(".rs")
        )
    assert rust_sources, f"No Rust source files were found in {project}."

    run_checked(["cargo", "build", "--manifest-path", manifest], timeout=180)

    with tempfile.TemporaryDirectory(prefix="normalizer-verifier-") as temporary:
        input_dir = os.path.join(temporary, "input")
        output_dir = os.path.join(temporary, "output")
        nested_dir = os.path.join(input_dir, "nested", "deep")
        external_dir = os.path.join(temporary, "linked_source")
        os.makedirs(nested_dir)
        os.makedirs(external_dir)

        token = uuid.uuid4().hex
        root_name = f"root_{token}.dat"
        nested_name = f"nested_{token}.dat"
        linked_name = f"linked_{token}.dat"

        samples = {
            os.path.join(input_dir, root_name): os.urandom(11) + bytes([0xE9, 0xFF, 0x80]),
            os.path.join(nested_dir, nested_name): bytes([0x00, 0x41, 0xF1, 0xA3]) + os.urandom(9),
            os.path.join(external_dir, linked_name): os.urandom(7) + bytes([0xC0, 0xD6, 0xFE]),
        }
        for path, content in samples.items():
            with open(path, "wb") as handle:
                handle.write(content)

        with open(os.path.join(input_dir, f"ignored_{token}.txt"), "wb") as handle:
            handle.write(bytes([0xE9, 0xF1]))
        with open(os.path.join(nested_dir, f"ignored_{token}.dat.bak"), "wb") as handle:
            handle.write(b"not a dat file")

        os.symlink(input_dir, os.path.join(nested_dir, "loop_to_root"))
        os.symlink(external_dir, os.path.join(input_dir, "linked_directory"))

        run_checked(
            ["cargo", "run", "--quiet", "--manifest-path", manifest, "--", input_dir, output_dir],
            timeout=20,
        )

        expected = {
            os.path.join(output_dir, os.path.splitext(root_name)[0] + ".utf8"): samples[os.path.join(input_dir, root_name)].decode("latin-1").encode("utf-8"),
            os.path.join(output_dir, "nested", "deep", os.path.splitext(nested_name)[0] + ".utf8"): samples[os.path.join(nested_dir, nested_name)].decode("latin-1").encode("utf-8"),
            os.path.join(output_dir, "linked_directory", os.path.splitext(linked_name)[0] + ".utf8"): samples[os.path.join(external_dir, linked_name)].decode("latin-1").encode("utf-8"),
        }

        found = []
        for root, _, files in os.walk(output_dir):
            for name in files:
                found.append(os.path.join(root, name))

        assert sorted(found) == sorted(expected), (
            f"Unexpected output files for unseen input. Expected {sorted(expected)}, got {sorted(found)}"
        )
        for path, expected_content in expected.items():
            assert stat.S_ISREG(os.lstat(path).st_mode), f"Output {path} is not a regular file."
            with open(path, "rb") as handle:
                actual_content = handle.read()
            assert actual_content == expected_content, (
                f"Output {path} was not converted correctly from ISO-8859-1 to UTF-8."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
