#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import pathlib
import pwd
import secrets
import shutil
import subprocess
import tarfile
import time
import zipfile


def test_audit_log_contents():
    log_path = "/home/user/artifact_audit.log"
    assert os.path.isfile(log_path), f"Audit log file is missing at {log_path}."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "[REJECTED] broken_data.zip: Corrupted",
        "[REJECTED] malicious_payload.zip: Path Traversal",
        "[REJECTED] sneaky_lib.tar.gz: Path Traversal"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, (
        f"Audit log contents do not match expected.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_quarantine_directory_contents():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Quarantine directory missing at {quarantine_dir}."

    expected_files = {"broken_data.zip", "malicious_payload.zip", "sneaky_lib.tar.gz"}
    actual_files = set(os.listdir(quarantine_dir))

    assert actual_files == expected_files, (
        f"Quarantine directory does not contain exactly the expected files.\n"
        f"Expected: {expected_files}\n"
        f"Actual: {actual_files}"
    )


def test_curated_artifacts_extracted():
    curated_dir = "/home/user/curated_artifacts"
    assert os.path.isdir(curated_dir), f"Curated artifacts directory missing at {curated_dir}."

    safe_app_main = os.path.join(curated_dir, "safe_app", "app", "main.py")
    safe_app_data = os.path.join(curated_dir, "safe_app", "app", "data.bin")
    safe_lib_util = os.path.join(curated_dir, "safe_lib", "lib", "util.py")

    assert os.path.isfile(safe_app_main), f"Expected extracted file is missing: {safe_app_main}"
    assert os.path.isfile(safe_app_data), f"Expected extracted file is missing: {safe_app_data}"
    assert os.path.isfile(safe_lib_util), f"Expected extracted file is missing: {safe_lib_util}"

    assert pathlib.Path(safe_app_main).read_bytes() == b"print('hello')"
    assert pathlib.Path(safe_app_data).read_bytes() == b"\x00\x01\x02"
    assert pathlib.Path(safe_lib_util).read_bytes() == b"def foo(): pass"


def test_incoming_directory_is_empty():
    incoming_dir = "/home/user/incoming_artifacts"
    assert os.path.isdir(incoming_dir), f"Incoming artifacts directory missing at {incoming_dir}."

    actual_files = os.listdir(incoming_dir)
    assert len(actual_files) == 0, f"Incoming directory should be empty, but contains: {actual_files}"


def test_dynamic_behavior_and_atomic_extraction():
    script = pathlib.Path("/home/user/curate_artifacts.py")
    assert script.is_file() and not script.is_symlink(), (
        "/home/user/curate_artifacts.py must exist as a regular file"
    )
    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", str(script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stdout

    base = pathlib.Path("/home/user")
    incoming = base / "incoming_artifacts"
    curated = base / "curated_artifacts"
    quarantine = base / "quarantine"
    audit = base / "artifact_audit.log"

    for path in (incoming, curated, quarantine):
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(mode=0o777)
        path.chmod(0o777)
    if audit.exists() or audit.is_symlink():
        audit.unlink()

    token = secrets.token_hex(8)
    safe_zip_name = f"bundle_{token}.zip"
    safe_tar_name = f"library_{token}.tar.gz"
    bad_rel_zip_name = f"relative_{token}.zip"
    bad_abs_zip_name = f"absolute_{token}.zip"
    bad_tar_name = f"traversal_{token}.tar.gz"
    corrupt_zip_name = f"corrupt_{token}.zip"
    corrupt_tar_name = f"corrupt_{token}.tar.gz"

    zip_members = {}
    with zipfile.ZipFile(incoming / safe_zip_name, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        # Numerous entries plus a delayed read hook make a directly-visible extraction
        # reliably observable while still keeping the test small.
        for i in range(80):
            name = f"payload/part_{i:03d}.bin"
            data = secrets.token_bytes(1024 + i)
            zip_members[name] = data
            zf.writestr(name, data)
        zip_members["payload/final.txt"] = ("complete-" + token).encode()
        zf.writestr("payload/final.txt", zip_members["payload/final.txt"])

    tar_members = {
        "src/module.py": ("VALUE = '" + token + "'\n").encode(),
        "assets/blob.bin": secrets.token_bytes(257),
    }
    with tarfile.open(incoming / safe_tar_name, "w:gz") as tf:
        for name, data in tar_members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))

    relative_escape = base / f"zip_escape_{token}"
    absolute_escape = pathlib.Path(f"/tmp/absolute_escape_{token}")
    tar_escape = base / f"tar_escape_{token}"
    for path in (relative_escape, absolute_escape, tar_escape):
        if path.exists() or path.is_symlink():
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()

    with zipfile.ZipFile(incoming / bad_rel_zip_name, "w") as zf:
        zf.writestr(f"../../zip_escape_{token}", b"escaped")
        zf.writestr("ordinary.txt", b"must not be extracted")

    with zipfile.ZipFile(incoming / bad_abs_zip_name, "w") as zf:
        zf.writestr(str(absolute_escape), b"escaped")

    with tarfile.open(incoming / bad_tar_name, "w:gz") as tf:
        data = b"escaped"
        info = tarfile.TarInfo(f"../../tar_escape_{token}")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))

    (incoming / corrupt_zip_name).write_bytes(b"PK\x03\x04" + secrets.token_bytes(37))
    (incoming / corrupt_tar_name).write_bytes(b"not-a-gzip-stream-" + secrets.token_bytes(31))

    rejected_names = {
        bad_rel_zip_name,
        bad_abs_zip_name,
        bad_tar_name,
        corrupt_zip_name,
        corrupt_tar_name,
    }
    archive_hashes = {
        name: hashlib.sha256((incoming / name).read_bytes()).hexdigest()
        for name in rejected_names
    }

    hook_dir = pathlib.Path("/tmp/curator_verifier_hook")
    if hook_dir.exists():
        shutil.rmtree(hook_dir)
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "import time, zipfile\n"
        "_original_read = zipfile.ZipExtFile.read\n"
        "def _slow_read(self, *args, **kwargs):\n"
        "    data = _original_read(self, *args, **kwargs)\n"
        "    if data:\n"
        "        time.sleep(0.004)\n"
        "    return data\n"
        "zipfile.ZipExtFile.read = _slow_read\n"
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir)
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    proc = subprocess.Popen(
        ["python3", str(script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
        preexec_fn=demote,
    )

    final_zip_dir = curated / safe_zip_name[:-4]
    partial_visible = False
    deadline = time.monotonic() + 30
    while proc.poll() is None:
        if time.monotonic() > deadline:
            proc.kill()
            output, _ = proc.communicate()
            raise AssertionError(f"curate_artifacts.py timed out. Output:\n{output}")
        if final_zip_dir.exists():
            for member, expected in zip_members.items():
                candidate = final_zip_dir / member
                try:
                    if not candidate.is_file() or candidate.read_bytes() != expected:
                        partial_visible = True
                        break
                except OSError:
                    partial_visible = True
                    break
        time.sleep(0.001)

    output, _ = proc.communicate()
    assert proc.returncode == 0, f"curate_artifacts.py failed with output:\n{output}"
    assert not partial_visible, "A partially extracted final destination became visible"

    assert incoming.is_dir()
    assert os.listdir(incoming) == [], f"Incoming directory is not empty: {os.listdir(incoming)}"

    expected_curated_dirs = {safe_zip_name[:-4], safe_tar_name[:-7]}
    assert set(os.listdir(curated)) == expected_curated_dirs

    for member, expected in zip_members.items():
        path = final_zip_dir / member
        assert path.is_file(), f"Missing ZIP member: {path}"
        assert path.read_bytes() == expected, f"Wrong ZIP member contents: {path}"

    final_tar_dir = curated / safe_tar_name[:-7]
    for member, expected in tar_members.items():
        path = final_tar_dir / member
        assert path.is_file(), f"Missing TAR member: {path}"
        assert path.read_bytes() == expected, f"Wrong TAR member contents: {path}"

    expected_zip_files = set(zip_members)
    actual_zip_files = {
        str(p.relative_to(final_zip_dir)) for p in final_zip_dir.rglob("*") if p.is_file()
    }
    assert actual_zip_files == expected_zip_files
    expected_tar_files = set(tar_members)
    actual_tar_files = {
        str(p.relative_to(final_tar_dir)) for p in final_tar_dir.rglob("*") if p.is_file()
    }
    assert actual_tar_files == expected_tar_files

    assert set(os.listdir(quarantine)) == rejected_names
    for name, expected_hash in archive_hashes.items():
        quarantined = quarantine / name
        assert quarantined.is_file()
        assert hashlib.sha256(quarantined.read_bytes()).hexdigest() == expected_hash

    expected_log = {
        f"[REJECTED] {bad_rel_zip_name}: Path Traversal",
        f"[REJECTED] {bad_abs_zip_name}: Path Traversal",
        f"[REJECTED] {bad_tar_name}: Path Traversal",
        f"[REJECTED] {corrupt_zip_name}: Corrupted",
        f"[REJECTED] {corrupt_tar_name}: Corrupted",
    }
    assert audit.is_file()
    actual_log = {line.strip() for line in audit.read_text().splitlines() if line.strip()}
    assert actual_log == expected_log, f"Expected {expected_log}, got {actual_log}"

    assert not relative_escape.exists(), "ZIP traversal wrote outside its extraction root"
    assert not absolute_escape.exists(), "Absolute ZIP member wrote outside its extraction root"
    assert not tar_escape.exists(), "TAR traversal wrote outside its extraction root"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
