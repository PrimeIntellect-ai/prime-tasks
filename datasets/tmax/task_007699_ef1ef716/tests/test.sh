#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import fcntl
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

ARTIFACTS = "/home/user/artifacts"
SCRIPT = "/home/user/curate.py"

EXPECTED = {
    "art1.meta": "name: package_A\narchitecture: x86_64\nversion: 1.0.1\nstatus: curated\n",
    "art2.meta": "name: package_B\narchitecture: arm64\nversion: 2.1.0\nstatus: pending\n",
    "art3.meta": "name: package_C\narchitecture: x86_64\nversion: 3.0.0\nstatus: curated\n",
    "art4.meta": "name: package_D\narchitecture: x86_64\nversion: 1.1.5\nstatus: curated\n",
}


def read_text(path):
    with open(path, "r", newline="") as f:
        return f.read()


def normalized_tar_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.lstrip("/")


def test_curate_script_exists_and_uses_flock():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."

    with open(SCRIPT, "r") as f:
        content = f.read()

    # Retain the original assertion and additionally require a real Python call.
    assert "fcntl.flock" in content, "The script does not appear to use fcntl.flock as requested."
    tree = ast.parse(content, filename=SCRIPT)
    calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "flock"
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "fcntl"
    ]
    assert calls, "curate.py does not contain an actual fcntl.flock(...) call."


def test_metadata_files_updated():
    # Retain the original assertions.
    art1_content = read_text(os.path.join(ARTIFACTS, "art1.meta"))
    assert "status: curated" in art1_content, "art1.meta was not updated correctly."
    assert "status: pending" not in art1_content, "art1.meta still has status: pending."

    art4_content = read_text(os.path.join(ARTIFACTS, "art4.meta"))
    assert "status: curated" in art4_content, "art4.meta was not updated correctly."
    assert "status: pending" not in art4_content, "art4.meta still has status: pending."

    assert art1_content == EXPECTED["art1.meta"], "art1.meta has changes other than the required status update."
    assert art4_content == EXPECTED["art4.meta"], "art4.meta has changes other than the required status update."


def test_metadata_files_untouched():
    # Retain the original assertions.
    art2_content = read_text(os.path.join(ARTIFACTS, "art2.meta"))
    assert "status: pending" in art2_content, "art2.meta should not have been updated."

    art3_content = read_text(os.path.join(ARTIFACTS, "art3.meta"))
    assert "status: curated" in art3_content, "art3.meta should remain curated."

    assert art2_content == EXPECTED["art2.meta"], "art2.meta was otherwise modified."
    assert art3_content == EXPECTED["art3.meta"], "art3.meta was otherwise modified."


def test_incremental_backup():
    backup_path = "/home/user/backup_inc.tar"
    assert os.path.isfile(backup_path), f"Incremental backup {backup_path} does not exist."

    with tarfile.open(backup_path, "r") as tar:
        names = tar.getnames()

        # Retain the original assertions.
        assert any("art1.meta" in name for name in names), "art1.meta is missing from the incremental backup."
        assert any("art4.meta" in name for name in names), "art4.meta is missing from the incremental backup."
        assert not any("art2.meta" in name for name in names), "art2.meta should not be in the incremental backup."
        assert not any("art3.meta" in name for name in names), "art3.meta should not be in the incremental backup."
        assert not any(name.endswith(".bin") for name in names), "Binary files should not be in the incremental backup."

        regular = [member for member in tar.getmembers() if member.isfile()]
        regular_names = [normalized_tar_name(member.name) for member in regular]
        expected_names = {
            "home/user/artifacts/art1.meta",
            "home/user/artifacts/art4.meta",
        }
        assert len(regular_names) == 2, "The incremental archive must contain exactly the two modified regular files."
        assert set(regular_names) == expected_names, "The incremental archive contains incorrect file paths."

        for member in regular:
            normalized = normalized_tar_name(member.name)
            basename = os.path.basename(normalized)
            extracted = tar.extractfile(member)
            assert extracted is not None
            data = extracted.read()
            assert data == EXPECTED[basename].encode(), f"Archived contents of {basename} are incorrect."


def test_script_behavior_and_real_exclusive_locking():
    token = uuid.uuid4().hex
    target_name = f"target_{token}.meta"
    arm_name = f"arm_{token}.meta"
    near_name = f"near_{token}.meta"
    curated_name = f"curated_{token}.meta"
    other_name = f"other_{token}.txt"

    initial = {
        target_name: f"name: randomized_{token}\nnote: status: pending is mentioned here\narchitecture: x86_64\nversion: 9.7\nstatus: pending\nchecksum: {token}\n",
        arm_name: f"name: arm_{token}\narchitecture: arm64\nstatus: pending\n",
        near_name: f"name: near_{token}\narchitecture: x86_64-extra\nstatus: pending\n",
        curated_name: f"name: done_{token}\narchitecture: x86_64\nstatus: curated\n",
        other_name: f"architecture: x86_64\nstatus: pending\nvalue: {token}\n",
    }
    expected_target = initial[target_name].replace("\nstatus: pending\n", "\nstatus: curated\n", 1)

    parent = os.path.dirname(ARTIFACTS)
    saved_dir = tempfile.mkdtemp(prefix="artifacts_saved_", dir=parent)
    os.rmdir(saved_dir)
    log_path = os.path.join(tempfile.gettempdir(), f"flock_{token}.log")
    launcher_path = os.path.join(tempfile.gettempdir(), f"launcher_{token}.py")

    launcher = r'''import os, runpy, sys, types
import fcntl as real_fcntl
log_path, script_path = sys.argv[1], sys.argv[2]
proxy = types.ModuleType("fcntl")
for key in dir(real_fcntl):
    setattr(proxy, key, getattr(real_fcntl, key))
def monitored_flock(fd, operation):
    number = fd if isinstance(fd, int) else fd.fileno()
    try:
        path = os.readlink("/proc/self/fd/%d" % number)
    except OSError:
        path = "<unknown>"
    with open(log_path, "a") as log:
        log.write("%d\\t%s\\n" % (operation, path))
        log.flush()
    return real_fcntl.flock(fd, operation)
proxy.flock = monitored_flock
sys.modules["fcntl"] = proxy
runpy.run_path(script_path, run_name="__main__")
'''

    proc = None
    lock_file = None
    try:
        os.rename(ARTIFACTS, saved_dir)
        os.mkdir(ARTIFACTS)
        for name, content in initial.items():
            with open(os.path.join(ARTIFACTS, name), "w", newline="") as f:
                f.write(content)

        with open(launcher_path, "w") as f:
            f.write(launcher)

        target_path = os.path.join(ARTIFACTS, target_name)
        lock_file = open(target_path, "r+")
        fcntl.flock(lock_file, fcntl.LOCK_EX)

        proc = subprocess.Popen(
            [sys.executable, launcher_path, log_path, SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        saw_target_exclusive = False
        deadline = time.time() + 5
        while time.time() < deadline:
            if os.path.exists(log_path):
                with open(log_path) as f:
                    records = [line.rstrip("\n").split("\t", 1) for line in f if "\t" in line]
                for operation, path in records:
                    op = int(operation)
                    if path == target_path and (op & fcntl.LOCK_EX) == fcntl.LOCK_EX:
                        saw_target_exclusive = True
                        break
            if saw_target_exclusive or proc.poll() is not None:
                break
            time.sleep(0.05)

        assert saw_target_exclusive, "curate.py did not invoke fcntl.flock with an exclusive lock on the metadata file."
        time.sleep(0.3)
        assert proc.poll() is None, "curate.py did not block on an exclusive lock held by another process."

        fcntl.flock(lock_file, fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None

        stdout, stderr = proc.communicate(timeout=8)
        assert proc.returncode == 0, f"curate.py failed on generated metadata:\n{stdout}\n{stderr}"

        with open(log_path) as f:
            records = [line.rstrip("\n").split("\t", 1) for line in f if "\t" in line]
        assert any(
            path == target_path and (int(operation) & fcntl.LOCK_UN) == fcntl.LOCK_UN
            for operation, path in records
        ), "curate.py did not explicitly release the metadata file lock with fcntl.LOCK_UN."

        assert read_text(target_path) == expected_target, "Generated matching metadata was not updated exactly as required."
        for name in (arm_name, near_name, curated_name, other_name):
            assert read_text(os.path.join(ARTIFACTS, name)) == initial[name], f"{name} should have remained byte-for-byte unchanged."
    finally:
        if lock_file is not None:
            fcntl.flock(lock_file, fcntl.LOCK_UN)
            lock_file.close()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if os.path.isdir(ARTIFACTS):
            shutil.rmtree(ARTIFACTS)
        if os.path.exists(saved_dir):
            os.rename(saved_dir, ARTIFACTS)
        for path in (log_path, launcher_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
