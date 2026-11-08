#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import tarfile
import pytest

def test_tarball_exists_and_contents(tmp_path):
    tarball_path = "/home/user/quick_prints.tar.gz"
    assert os.path.isfile(tarball_path), f"Tarball {tarball_path} does not exist."

    expected_files = {
        "quick_prints/bench.gcode",
        "quick_prints/token.gcode",
        "quick_prints/almost.gcode"
    }

    unexpected_files = {
        "quick_prints/big_statue.gcode",
        "quick_prints/edge_case.gcode",
        "quick_prints/invalid.txt"
    }

    with tarfile.open(tarball_path, "r:gz") as tar:
        members = tar.getnames()

        # Check that expected files are in the tarball
        for f in expected_files:
            assert f in members, f"Expected file {f} missing from tarball {tarball_path}."

        # Check that unexpected files are NOT in the tarball
        for f in unexpected_files:
            assert f not in members, f"Unexpected file {f} found in tarball {tarball_path}."

def test_hard_links_created():
    quick_prints_dir = "/home/user/quick_prints"
    gcode_dir = "/home/user/gcode_files"

    assert os.path.isdir(quick_prints_dir), f"Directory {quick_prints_dir} does not exist."

    expected_files = ["bench.gcode", "token.gcode", "almost.gcode"]

    for filename in expected_files:
        src_path = os.path.join(gcode_dir, filename)
        dest_path = os.path.join(quick_prints_dir, filename)

        assert os.path.isfile(dest_path), f"Expected file {dest_path} does not exist."

        src_stat = os.stat(src_path)
        dest_stat = os.stat(dest_path)

        assert src_stat.st_ino == dest_stat.st_ino, f"{dest_path} is not a hard link to {src_path}."
        assert src_stat.st_dev == dest_stat.st_dev, f"{dest_path} and {src_path} are on different devices."

def test_no_extra_files_in_quick_prints():
    quick_prints_dir = "/home/user/quick_prints"
    if not os.path.isdir(quick_prints_dir):
        pytest.fail(f"Directory {quick_prints_dir} does not exist.")

    actual_files = set(os.listdir(quick_prints_dir))
    expected_files = {"bench.gcode", "token.gcode", "almost.gcode"}

    extra_files = actual_files - expected_files
    assert not extra_files, f"Unexpected files found in {quick_prints_dir}: {extra_files}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_behavior.py
import os
import pwd
import random
import shutil
import stat
import subprocess
import tempfile
import uuid

SOURCE = "/home/user/organize.cpp"
SUBMITTED_BINARY = "/home/user/organize"
GCODE_DIR = "/home/user/gcode_files"
QUICK_DIR = "/home/user/quick_prints"


def require_regular(path):
    assert os.path.exists(path), f"Required artifact {path} does not exist"
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file"


require_regular(SOURCE)
require_regular(SUBMITTED_BINARY)
assert os.access(SUBMITTED_BINARY, os.X_OK), f"{SUBMITTED_BINARY} is not executable"
with open(SUBMITTED_BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{SUBMITTED_BINARY} is not a compiled executable"

# Add unpredictable inputs after the agent has finished, preventing a solution
# that merely hard-codes the image's original filenames.
tag = uuid.uuid4().hex
fast_name = f"quick_{tag}.gcode"
slow_name = f"slow_{tag}.gcode"
missing_name = f"missing_{tag}.gcode"
fast_count = random.SystemRandom().randint(1, 49)
slow_count = random.SystemRandom().randint(50, 700)

fixtures = {
    fast_name: f"; generated test\n; LAYER_COUNT: {fast_count}\nG1 X1 Y1\n",
    slow_name: f"; generated test\n; LAYER_COUNT: {slow_count}\nG1 X2 Y2\n",
    missing_name: "; generated test without layer metadata\nG1 X3 Y3\n",
}
for name, contents in fixtures.items():
    with open(os.path.join(GCODE_DIR, name), "w", encoding="utf-8") as f:
        f.write(contents)
    os.chmod(os.path.join(GCODE_DIR, name), 0o644)

# A directory is not a standard file and must be ignored.
os.mkdir(os.path.join(GCODE_DIR, f"directory_{tag}.gcode"))


def derive_expected():
    expected = set()
    prefix = "; LAYER_COUNT:"
    for entry in os.scandir(GCODE_DIR):
        if not entry.is_file(follow_symlinks=False):
            continue
        count = None
        with open(entry.path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith(prefix):
                    try:
                        count = int(line[len(prefix):].strip())
                    except ValueError:
                        count = None
                    break
        if count is not None and count < 50:
            expected.add(entry.name)
    return expected


expected = derive_expected()
assert fast_name in expected
assert slow_name not in expected
assert missing_name not in expected

user = pwd.getpwnam("user")


def demote():
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


def reset_output():
    if os.path.lexists(QUICK_DIR):
        if os.path.isdir(QUICK_DIR) and not os.path.islink(QUICK_DIR):
            shutil.rmtree(QUICK_DIR)
        else:
            os.unlink(QUICK_DIR)
    os.mkdir(QUICK_DIR, 0o777)
    os.chmod(QUICK_DIR, 0o777)


def run_and_check(binary):
    reset_output()
    result = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    actual = set(os.listdir(QUICK_DIR))
    assert actual == expected, f"Expected quick_prints entries {expected}, got {actual}"
    for name in expected:
        src = os.path.join(GCODE_DIR, name)
        dst = os.path.join(QUICK_DIR, name)
        assert stat.S_ISREG(os.lstat(dst).st_mode), f"{dst} is not a regular file"
        src_stat = os.stat(src)
        dst_stat = os.stat(dst)
        assert src_stat.st_ino == dst_stat.st_ino, f"{dst} is not a hard link to {src}"
        assert src_stat.st_dev == dst_stat.st_dev, f"{dst} and {src} are on different devices"


# Exercise the executable the agent submitted.
run_and_check(SUBMITTED_BINARY)

# Independently compile and exercise the submitted source, ensuring the source
# itself implements the requested behavior rather than merely existing.
with tempfile.TemporaryDirectory(prefix="organize_verify_") as build_dir:
    rebuilt = os.path.join(build_dir, "organize")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"organize.cpp failed to compile as C++17\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    run_and_check(rebuilt)
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_dynamic_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
