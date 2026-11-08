#!/bin/bash
set +e
mkdir -p /logs/verifier

run_checks() (
set -e

cat << 'PY' > /tmp/test_original_state.py
import os
import tarfile
import pytest

def test_extracted_directories():
    success_101 = "/home/user/curated/build_101"
    success_103 = "/home/user/curated/build_103"
    failure_102 = "/home/user/curated/build_102"
    failure_104 = "/home/user/curated/build_104"
    assert os.path.isdir(success_101), f"Expected extracted directory missing: {success_101}"
    assert os.path.isdir(success_103), f"Expected extracted directory missing: {success_103}"
    assert not os.path.exists(failure_102), f"Failed build should not have been extracted: {failure_102}"
    assert not os.path.exists(failure_104), f"Failed build should not have been extracted: {failure_104}"

def test_latest_symlink():
    symlink_path = "/home/user/curated/latest"
    assert os.path.islink(symlink_path), f"Expected a symbolic link at {symlink_path}"
    target = os.readlink(symlink_path)
    expected_target = "build_103"
    assert target == expected_target, f"Symlink points to '{target}' instead of '{expected_target}'"

def test_hardlinks_created():
    file1 = "/home/user/curated/build_101/lib.so"
    file2 = "/home/user/curated/build_103/lib.so"
    assert os.path.isfile(file1), f"Expected file missing: {file1}"
    assert os.path.isfile(file2), f"Expected file missing: {file2}"
    inode1 = os.stat(file1).st_ino
    inode2 = os.stat(file2).st_ino
    assert inode1 == inode2, (
        f"Deduplication failed: {file1} (inode {inode1}) and "
        f"{file2} (inode {inode2}) do not share the same inode."
    )

def test_backup_created():
    backup_path = "/home/user/curated_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file missing: {backup_path}"
    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            members = tar.getnames()
            assert len(members) > 0, "Backup archive is empty."
    except tarfile.ReadError:
        pytest.fail(f"Backup file {backup_path} is not a valid gzip-compressed tar archive.")
PY
python3 -m pytest /tmp/test_original_state.py -x --tb=short

python3 << 'PY'
import hashlib
import json
import os
import pwd
import random
import shutil
import subprocess
import tarfile
import tempfile

script = "/home/user/curate_artifacts.sh"
assert os.path.isfile(script) and not os.path.islink(script), "curate_artifacts.sh must be a regular file"
mode = os.stat(script).st_mode
assert mode & 0o111, "curate_artifacts.sh is not executable"
with open(script, "rb") as f:
    first = f.readline(256)
assert first.startswith(b"#!") and b"bash" in first, "curate_artifacts.sh must be an executable Bash script"

base = random.SystemRandom().randint(20000, 80000)
ids = [base + 3, base + 17, base + 41, base + 66]
s1, failed, s2, s3 = ids
success = [s1, s2, s3]

incoming = "/home/user/incoming"
archives = os.path.join(incoming, "archives")
curated = "/home/user/curated"
shutil.rmtree(incoming, ignore_errors=True)
shutil.rmtree(curated, ignore_errors=True)
os.makedirs(archives, mode=0o777)
os.makedirs(curated, mode=0o777)
os.chmod(incoming, 0o777)
os.chmod(archives, 0o777)
os.chmod(curated, 0o777)

common = b"runtime-generated-common-" + os.urandom(24)
cross = b"runtime-generated-cross-name-" + os.urandom(24)
expected = {
    s1: {
        "app.bin": f"unique-{s1}".encode(),
        "lib/lib.so": common,
        "copies/local-copy.dat": common,
        "nested/alpha.dat": cross,
        "empty-a": b"",
    },
    failed: {
        "failed-only.bin": b"this archive must never be extracted",
        "lib/lib.so": common,
    },
    s2: {
        "app.bin": f"unique-{s2}".encode(),
        "lib/lib.so": common,
        "different/name.bin": cross,
        "empty-b": b"",
    },
    s3: {
        "app.bin": f"unique-{s3}".encode(),
        "deep/lib-again.so": common,
        "other/cross-copy": cross,
    },
}

for build_id, files in expected.items():
    root = tempfile.mkdtemp(prefix=f"fixture-{build_id}-")
    try:
        for rel, data in files.items():
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
        with tarfile.open(os.path.join(archives, f"build_{build_id}.tar"), "w") as tf:
            for rel in sorted(files):
                tf.add(os.path.join(root, rel), arcname=rel, recursive=False)
    finally:
        shutil.rmtree(root)

log = f'''--- BUILD {s2} ---
compiler output line one
compiler output line two
STATUS: SUCCESS
--- BUILD {failed} ---
a stale diagnostic says the following line, but the record continues
STATUS: SUCCESS
retry failed permanently
STATUS: FAILURE
--- BUILD {s1} ---
linking artifact
STATUS: SUCCESS
--- BUILD {s3} ---
several
multi-line
messages
STATUS: SUCCESS
'''
with open(os.path.join(incoming, "builds.log"), "w") as f:
    f.write(log)

# Seed a genuine prior incremental state, then remove its old payload so the
# submitted script must record deletions/new builds and update the snapshot.
baseline = os.path.join(curated, "baseline")
os.makedirs(baseline)
with open(os.path.join(baseline, "old.txt"), "w") as f:
    f.write("old baseline data")
for p in ("/home/user/backup.snar", "/home/user/curated_backup.tar.gz"):
    try:
        os.remove(p)
    except FileNotFoundError:
        pass
subprocess.run([
    "tar", "--listed-incremental=/home/user/backup.snar", "-czf",
    "/tmp/verifier_baseline.tar.gz", "-C", "/home/user", "curated"
], check=True)
with open("/home/user/backup.snar", "rb") as f:
    before_snar = hashlib.sha256(f.read()).hexdigest()
shutil.rmtree(baseline)

uid = pwd.getpwnam("user").pw_uid
gid = pwd.getpwnam("user").pw_gid
for root, dirs, files in os.walk(incoming):
    os.chown(root, uid, gid)
    for name in dirs:
        os.chown(os.path.join(root, name), uid, gid)
    for name in files:
        os.chown(os.path.join(root, name), uid, gid)
os.chown(curated, uid, gid)
os.chown("/home/user/backup.snar", uid, gid)
os.chmod("/home/user/backup.snar", 0o666)

fixture = {
    "success": success,
    "failed": failed,
    "before_snar": before_snar,
    "expected": {str(k): {p: v.hex() for p, v in files.items()} for k, files in expected.items()},
}
with open("/tmp/dynamic_fixture.json", "w") as f:
    json.dump(fixture, f)
PY

runuser -u user -- timeout 60 /home/user/curate_artifacts.sh

python3 << 'PY'
import hashlib
import json
import os
import tarfile

with open("/tmp/dynamic_fixture.json") as f:
    fixture = json.load(f)
success = fixture["success"]
failed = fixture["failed"]
expected = {
    int(k): {p: bytes.fromhex(v) for p, v in files.items()}
    for k, files in fixture["expected"].items()
}
curated = "/home/user/curated"

for build_id in success:
    root = os.path.join(curated, f"build_{build_id}")
    assert os.path.isdir(root), f"successful build {build_id} was not extracted"
    actual_files = set()
    for walk_root, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(walk_root, name)
            assert not os.path.islink(path), f"archive file unexpectedly extracted as symlink: {path}"
            rel = os.path.relpath(path, root)
            actual_files.add(rel)
            with open(path, "rb") as f:
                assert f.read() == expected[build_id][rel], f"wrong extracted content in {path}"
    assert actual_files == set(expected[build_id]), f"wrong extracted file set for build {build_id}"

assert not os.path.exists(os.path.join(curated, f"build_{failed}")), "failed build was extracted"
actual_build_dirs = {
    name for name in os.listdir(curated)
    if name.startswith("build_") and os.path.isdir(os.path.join(curated, name))
}
assert actual_build_dirs == {f"build_{i}" for i in success}, "unexpected build directories were curated"

latest = os.path.join(curated, "latest")
assert os.path.islink(latest), "latest is not a symbolic link"
assert os.readlink(latest) == f"build_{max(success)}", "latest does not use the highest numeric successful ID"

# Every equal-content group in the generated hierarchy must be one inode,
# including duplicates with different names and duplicates within one build.
groups = {}
for build_id in success:
    root = os.path.join(curated, f"build_{build_id}")
    for walk_root, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(walk_root, name)
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).digest()
            groups.setdefault(digest, []).append(path)
for paths in groups.values():
    if len(paths) > 1:
        identities = {(os.stat(p).st_dev, os.stat(p).st_ino) for p in paths}
        assert len(identities) == 1, f"identical files were not hard-linked: {paths}"

backup = "/home/user/curated_backup.tar.gz"
assert os.path.isfile(backup), "incremental backup was not created"
with open("/home/user/backup.snar", "rb") as f:
    after_snar = hashlib.sha256(f.read()).hexdigest()
assert after_snar != fixture["before_snar"], "incremental snapshot state was not updated"

with tarfile.open(backup, "r:gz") as tf:
    members = tf.getmembers()
    assert members, "backup archive is empty"
    assert any(m.type == b"D" for m in members), "backup is not a GNU listed-incremental archive"
    for build_id in success:
        for rel, wanted in expected[build_id].items():
            suffix = f"build_{build_id}/{rel}"
            matches = [m for m in members if m.name.lstrip("./").endswith(suffix)]
            assert len(matches) == 1, f"backup is missing or duplicates {suffix}"
            stream = tf.extractfile(matches[0])
            assert stream is not None, f"backup member has no file data: {suffix}"
            assert stream.read() == wanted, f"backup contains wrong data for {suffix}"
    failed_suffix = f"build_{failed}/"
    assert not any(failed_suffix in m.name.lstrip("./") for m in members), "backup contains the failed build"
PY
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
