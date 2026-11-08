#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid
import pytest


def get_large_directories(base_dir, threshold_bytes=10 * 1024 * 1024):
    large_dirs = []
    if not os.path.isdir(base_dir):
        return large_dirs

    for d in os.listdir(base_dir):
        dir_path = os.path.join(base_dir, d)
        if os.path.isdir(dir_path):
            total_size = 0
            for dirpath, _, filenames in os.walk(dir_path):
                for f in filenames:
                    fp = os.path.join(dirpath, f)
                    if not os.path.islink(fp):
                        total_size += os.path.getsize(fp)
            if total_size > threshold_bytes:
                large_dirs.append(d)
    return large_dirs


def test_finops_fstab_generated():
    fstab_path = "/home/user/finops_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    large_dirs = get_large_directories("/home/user/s3_cache")
    assert len(large_dirs) > 0, "No large directories found to test against."

    expected_lines = []
    for d in large_dirs:
        expected_lines.append(f"/home/user/s3_cache/{d} /home/user/cold_tier/{d} none bind 0 0")

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {fstab_path}."

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines in {fstab_path}, found {len(lines)}."


def test_finops_env_generated():
    env_path = "/home/user/finops_env.sh"
    assert os.path.isfile(env_path), f"File {env_path} does not exist."

    with open(env_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    large_dirs = get_large_directories("/home/user/s3_cache")

    expected_lines = []
    for d in large_dirs:
        expected_lines.append(f"export {d.upper()}_STORAGE_TIER=cold")

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {env_path}."

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} lines in {env_path}, found {len(lines)}."


def test_systemd_service():
    service_path = "/home/user/.config/systemd/user/finops-tiering.service"
    assert os.path.isfile(service_path), f"Systemd service file {service_path} does not exist."

    with open(service_path, 'r') as f:
        content = f.read()

    assert "Type=oneshot" in content, f"'Type=oneshot' not found in {service_path}."
    assert "ExecStart=/usr/bin/python3 /home/user/finops_tiering.py" in content, f"Expected ExecStart not found in {service_path}."


def write_bytes(path, size):
    chunk = b'\0' * (1024 * 1024)
    with open(path, 'wb') as f:
        while size >= len(chunk):
            f.write(chunk)
            size -= len(chunk)
        if size:
            f.write(b'\0' * size)


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def test_script_exists_and_generates_outputs_from_sizes():
    script_path = "/home/user/finops_tiering.py"
    assert os.path.lexists(script_path), f"Python script {script_path} does not exist."
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"{script_path} must be a regular file, not a symlink or other file type."

    cache_path = "/home/user/s3_cache"
    fstab_path = "/home/user/finops_fstab"
    env_path = "/home/user/finops_env.sh"
    nonce = uuid.uuid4().hex
    cache_backup = f"/home/user/.s3_cache.verifier_backup.{nonce}"
    fstab_backup = f"/home/user/.finops_fstab.verifier_backup.{nonce}"
    env_backup = f"/home/user/.finops_env.verifier_backup.{nonce}"

    large_name = f"large_{uuid.uuid4().hex}"
    exact_name = f"exact_{uuid.uuid4().hex}"
    small_name = f"small_{uuid.uuid4().hex}"

    moved_cache = moved_fstab = moved_env = False
    try:
        os.rename(cache_path, cache_backup)
        moved_cache = True
        if os.path.lexists(fstab_path):
            os.rename(fstab_path, fstab_backup)
            moved_fstab = True
        if os.path.lexists(env_path):
            os.rename(env_path, env_backup)
            moved_env = True

        os.makedirs(os.path.join(cache_path, large_name, "nested"), mode=0o777)
        os.makedirs(os.path.join(cache_path, exact_name, "nested"), mode=0o777)
        os.makedirs(os.path.join(cache_path, small_name), mode=0o777)
        os.chmod(cache_path, 0o777)

        # The large directory exceeds the threshold only after recursively
        # summing two individually sub-threshold files.
        write_bytes(os.path.join(cache_path, large_name, "part1.bin"), 6 * 1024 * 1024)
        write_bytes(os.path.join(cache_path, large_name, "nested", "part2.bin"), 5 * 1024 * 1024)
        # Strictly equal to 10 MiB must not be selected.
        write_bytes(os.path.join(cache_path, exact_name, "part1.bin"), 4 * 1024 * 1024)
        write_bytes(os.path.join(cache_path, exact_name, "nested", "part2.bin"), 6 * 1024 * 1024)
        write_bytes(os.path.join(cache_path, small_name, "data.bin"), 1024 * 1024)

        result = subprocess.run(
            ["/usr/bin/python3", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {script_path} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        assert os.path.isfile(fstab_path), "The script did not generate /home/user/finops_fstab."
        assert os.path.isfile(env_path), "The script did not generate /home/user/finops_env.sh."

        with open(fstab_path, 'r') as f:
            fstab_lines = [line.strip() for line in f if line.strip()]
        with open(env_path, 'r') as f:
            env_lines = [line.strip() for line in f if line.strip()]

        expected_fstab = f"/home/user/s3_cache/{large_name} /home/user/cold_tier/{large_name} none bind 0 0"
        expected_env = f"export {large_name.upper()}_STORAGE_TIER=cold"
        assert fstab_lines == [expected_fstab], f"Unexpected generated fstab lines: {fstab_lines!r}"
        assert env_lines == [expected_env], f"Unexpected generated environment lines: {env_lines!r}"
    finally:
        remove_path(cache_path)
        remove_path(fstab_path)
        remove_path(env_path)
        if moved_cache and os.path.lexists(cache_backup):
            os.rename(cache_backup, cache_path)
        if moved_fstab and os.path.lexists(fstab_backup):
            os.rename(fstab_backup, fstab_path)
        if moved_env and os.path.lexists(env_backup):
            os.rename(env_backup, env_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
