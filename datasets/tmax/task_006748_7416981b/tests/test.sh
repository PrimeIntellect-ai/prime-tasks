#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
import zipfile


def test_flat_dataset_directory_exists():
    flat_dir = "/home/user/flat_dataset"
    assert os.path.exists(flat_dir), f"Directory {flat_dir} does not exist."
    assert os.path.isdir(flat_dir), f"Path {flat_dir} is not a directory."


def test_flat_dataset_files_and_content():
    flat_dir = "/home/user/flat_dataset"
    assert os.path.exists(flat_dir), f"Directory {flat_dir} does not exist."

    expected_files = {
        "region_A_station_1_data_log.txt": "DATA_A1\n",
        "region_A_station_2_data_log.txt": "DATA_A2\n",
        "region_B_station_3_data_log.txt": "DATA_B3\n"
    }

    actual_files = set(os.listdir(flat_dir))
    expected_filenames = set(expected_files.keys())

    missing_files = expected_filenames - actual_files
    extra_files = actual_files - expected_filenames

    assert not missing_files, f"Missing expected files in {flat_dir}: {missing_files}"
    assert not extra_files, f"Found unexpected files in {flat_dir}: {extra_files}"

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(flat_dir, filename)
        with open(filepath, 'r') as f:
            content = f.read()
            assert content == expected_content, f"Content mismatch in {filename}. Expected '{expected_content}', got '{content}'."


def zip_bytes(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries.items():
            archive.writestr(name, content)
    return output.getvalue()


def tar_gz_bytes(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, content in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


def test_script_exists_and_recursively_processes_fresh_archives():
    script = "/home/user/process_dataset.py"
    assert os.path.exists(script), f"Required script {script} does not exist."
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode), f"{script} must be a regular file, not a symlink or directory."

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    raw_dir = "/home/user/raw_dataset"
    flat_dir = "/home/user/flat_dataset"
    shutil.rmtree(raw_dir, ignore_errors=True)
    shutil.rmtree(flat_dir, ignore_errors=True)
    os.makedirs(os.path.join(raw_dir, "incoming"), exist_ok=True)

    token = secrets.token_hex(8)
    outer = f"outer_{token}"
    inner = f"inner_{token}"
    deepest = f"deep_{token}"
    second = f"batch_{token}"
    child = f"station_{token}"
    payload_one = f"DYNAMIC_ONE_{secrets.token_hex(16)}\n".encode()
    payload_two = f"DYNAMIC_TWO_{secrets.token_hex(16)}\n".encode()

    deep_zip = zip_bytes({
        "data_log.txt": payload_one,
        "ignored.txt": b"not a log\n",
    })
    inner_tar = tar_gz_bytes({f"{deepest}.zip": deep_zip})
    outer_zip = zip_bytes({f"{inner}.tar.gz": inner_tar})
    with open(os.path.join(raw_dir, "incoming", f"{outer}.zip"), "wb") as f:
        f.write(outer_zip)

    child_zip = zip_bytes({"data_log.txt": payload_two})
    second_tar = tar_gz_bytes({f"{child}.zip": child_zip})
    with open(os.path.join(raw_dir, f"{second}.tar.gz"), "wb") as f:
        f.write(second_tar)

    result = subprocess.run(
        ["python3", script],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_dataset.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isdir(flat_dir), f"Script did not create {flat_dir}."

    expected = {
        f"{outer}_{inner}_{deepest}_data_log.txt": payload_one,
        f"{second}_{child}_data_log.txt": payload_two,
    }
    actual_names = set(os.listdir(flat_dir))
    assert actual_names == set(expected), (
        f"Fresh recursive extraction produced wrong files. "
        f"Expected {set(expected)}, got {actual_names}."
    )
    for name, content in expected.items():
        path = os.path.join(flat_dir, name)
        assert os.path.isfile(path), f"Expected regular output file {path}."
        with open(path, "rb") as f:
            assert f.read() == content, f"Incorrect content in {name}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
