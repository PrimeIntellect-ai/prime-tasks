#!/bin/bash
set -e
mkdir -p /logs/verifier

verify() {
    python3 - <<'PY' || return 1
import json
import os
import uuid

source = "/home/user/clean_backup.c"
exe = "/home/user/clean_backup"

assert os.path.isfile(source) and not os.path.islink(source), f"Missing regular C source: {source}"
assert os.path.isfile(exe) and not os.path.islink(exe), f"Missing regular executable: {exe}"
assert os.access(exe, os.X_OK), f"Executable bit not set on {exe}"
with open(exe, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{exe} is not an ELF executable"

token = uuid.uuid4().hex
probe_dir = os.path.join("/home/user/datasets", "verifier_probe_" + token)
deep_dir = os.path.join(probe_dir, "deep")
os.makedirs(deep_dir)
data_path = os.path.join(deep_dir, "probe_" + token + ".dat")
with open(data_path, "wb") as f:
    f.write(os.urandom(257) + b"\nverifier-generated-data\n")
loop_path = os.path.join(deep_dir, "back_to_probe")
os.symlink(probe_dir, loop_path)

with open("/tmp/clean_backup_challenge.json", "w") as f:
    json.dump({"data_path": data_path, "loop_path": loop_path}, f)
PY

    find /home/user/compressed -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
    rm -f /home/user/loop_report.txt || return 1

    gcc -o /home/user/clean_backup /home/user/clean_backup.c -lz || return 1

    python3 - <<'PY' || return 1
import os
p = "/home/user/clean_backup"
assert os.path.isfile(p) and not os.path.islink(p)
assert os.access(p, os.X_OK)
with open(p, "rb") as f:
    assert f.read(4) == b"\x7fELF"
PY

    ldd /home/user/clean_backup | grep -q 'libz\.so' || return 1
    nm -D /home/user/clean_backup | grep -Eq '[[:space:]]U[[:space:]]+gzopen(64)?(@|$)' || return 1
    nm -D /home/user/clean_backup | grep -Eq '[[:space:]]U[[:space:]]+gzwrite(@|$)' || return 1

    timeout 20s /home/user/clean_backup || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import subprocess
import pytest

with open("/tmp/clean_backup_challenge.json", "r") as f:
    challenge = json.load(f)


def test_loop_report_txt():
    report_path = "/home/user/loop_report.txt"
    assert os.path.isfile(report_path), f"Expected loop report file not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_loop1 = "/home/user/datasets/broken/chain/sym_loop1"
    expected_loop2_a = "/home/user/datasets/loopX/to_Y/to_X"
    expected_loop2_b = "/home/user/datasets/loopY/to_X/to_Y"
    expected_probe_loop = challenge["loop_path"]

    assert expected_loop1 in lines, f"Missing {expected_loop1} in loop_report.txt"

    loop2_found = (expected_loop2_a in lines) or (expected_loop2_b in lines)
    assert loop2_found, (
        "Missing cross-directory loop in loop_report.txt. Expected either "
        f"{expected_loop2_a} or {expected_loop2_b}"
    )

    assert expected_loop2_a in lines, f"Missing {expected_loop2_a} in loop_report.txt"
    assert expected_loop2_b in lines, f"Missing {expected_loop2_b} in loop_report.txt"
    assert expected_probe_loop in lines, f"Missing generated loop {expected_probe_loop}"

    expected_lines = {
        expected_loop1,
        expected_loop2_a,
        expected_loop2_b,
        expected_probe_loop,
    }
    assert set(lines) == expected_lines, (
        f"loop_report.txt contains fabricated, duplicate, or missing entries: {lines}"
    )
    assert len(lines) == len(expected_lines), "loop_report.txt contains duplicate entries"


def test_compressed_files():
    compressed_dir = "/home/user/compressed"
    assert os.path.isdir(compressed_dir), f"Compressed directory not found at {compressed_dir}"

    original_files = [
        "/home/user/datasets/expA/data1.dat",
        "/home/user/datasets/expA/sub_exp/data2.dat",
        "/home/user/datasets/expB/data3.dat",
        challenge["data_path"],
    ]

    expected_compressed_files = []

    for orig_path in original_files:
        assert os.path.isfile(orig_path), f"Original file {orig_path} missing, setup was altered."

        stat_res = os.stat(orig_path)
        inode = stat_res.st_ino
        filename = os.path.basename(orig_path)

        comp_filename = f"{filename}_{inode}.gz"
        comp_path = os.path.join(compressed_dir, comp_filename)
        expected_compressed_files.append(comp_filename)

        assert os.path.isfile(comp_path), f"Expected compressed file {comp_path} not found."

        with open(orig_path, "rb") as f:
            expected_content = f.read()

        try:
            with gzip.open(comp_path, "rb") as f:
                comp_content = f.read()
        except Exception as e:
            pytest.fail(f"Failed to decompress {comp_path}: {e}")

        assert comp_content == expected_content, f"Content mismatch in compressed file {comp_path}"
        result = subprocess.run(["gzip", "-t", "--", comp_path], capture_output=True)
        assert result.returncode == 0, (
            f"gzip -t failed for {comp_path}: {result.stderr.decode(errors='replace')}"
        )

    actual_files = os.listdir(compressed_dir)
    for f in actual_files:
        assert f in expected_compressed_files, f"Unexpected file found in compressed directory: {f}"
    assert set(actual_files) == set(expected_compressed_files), (
        f"Compressed directory contents differ: {actual_files}"
    )
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
