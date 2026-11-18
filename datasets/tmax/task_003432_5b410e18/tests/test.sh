#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import shutil
import signal
import stat
import subprocess
import tarfile
import tempfile
import uuid

import pytest


@pytest.fixture(scope="session", autouse=True)
def exercise_submission():
    script = "/home/user/curate.py"
    assert os.path.exists(script), f"Required script {script} does not exist."
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode) and not stat.S_ISLNK(mode), f"{script} must be a regular file."
    assert os.path.getsize(script) > 0, f"{script} is empty."

    token = uuid.uuid4().hex[:12]
    clean_1 = f"clean_{token}_1.elf"
    clean_2 = f"clean_{token}_2.elf"
    vulnerable = f"vulnerable_{token}.elf"
    deprecated = f"deprecated_{token}.elf"
    loop_a = f"loop_{token}_A"
    loop_b = f"loop_{token}_B"
    external = f"external_{token}"

    work = tempfile.mkdtemp(prefix="verifier_fixture_")
    source = os.path.join(work, "source")
    os.mkdir(source)

    files = {
        clean_1: os.urandom(2 * 1024 * 1024),
        clean_2: os.urandom(1 * 1024 * 1024),
        vulnerable: os.urandom(15 * 1024 * 1024),
        deprecated: os.urandom(10 * 1024 * 1024),
    }
    for name, data in files.items():
        with open(os.path.join(source, name), "wb") as f:
            f.write(data)

    archive = "/app/incoming/raw_artifacts.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        for name in files:
            tf.add(os.path.join(source, name), arcname=name, recursive=False)
        for name, target in ((loop_a, loop_b), (loop_b, loop_a), (external, "/etc/passwd")):
            info = tarfile.TarInfo(name)
            info.type = tarfile.SYMTYPE
            info.linkname = target
            info.mode = 0o777
            tf.addfile(info)

    with open("/app/logs/audit.log", "w", encoding="utf-8") as f:
        f.write(f"""BEGIN RECORD
ID: 201
Filename: {vulnerable}
Status: VULNERABLE
END RECORD
BEGIN RECORD
ID: 202
Filename: {clean_1}
Status: SECURE
END RECORD
BEGIN RECORD
ID: 203
Filename: {deprecated}
Status: DEPRECATED
END RECORD
BEGIN RECORD
ID: 204
Filename: {clean_2}
Status: SECURE
END RECORD
""")

    shutil.rmtree("/app/staging", ignore_errors=True)
    for path in ("/app/final_artifact.pck", "/app/logs/packer_out.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    packer = "/app/bin/packer"
    real_packer = os.path.join(work, "packer.real")
    invocation_log = os.path.join(work, "invocations")
    marker = f"PACKER_STDOUT_{uuid.uuid4().hex}"
    shutil.copy2(packer, real_packer)

    wrapper = f'''#!/bin/bash
printf '%s\\n' {marker!r}
printf '%s\\0' "$@" >> {invocation_log!r}
exec {real_packer!r} "$@"
'''
    with open(packer, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(packer, 0o755)

    def limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (10 * 1024 * 1024, 10 * 1024 * 1024))
        resource.setrlimit(resource.RLIMIT_CPU, (30, 30))

    proc = None
    try:
        proc = subprocess.Popen(
            ["python3", script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            preexec_fn=limits,
        )
        try:
            stdout, stderr = proc.communicate(timeout=45)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
            pytest.fail("curate.py did not finish within 45 seconds; it may have passed a symlink loop to the packer.")
        assert proc.returncode == 0, (
            f"curate.py exited with status {proc.returncode}.\n"
            f"stdout:\n{stdout.decode(errors='replace')}\n"
            f"stderr:\n{stderr.decode(errors='replace')}"
        )
    finally:
        shutil.copy2(real_packer, packer)
        os.chmod(packer, 0o755)

    assert os.path.isfile(invocation_log), "curate.py never invoked /app/bin/packer."
    with open(invocation_log, "rb") as f:
        args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    expected_args = ["/app/staging", "/app/final_artifact.pck"]
    assert any(args[i:i + 2] == expected_args for i in range(max(0, len(args) - 1))), (
        "The packer was not invoked as '/app/bin/packer /app/staging /app/final_artifact.pck'."
    )

    assert os.path.isdir("/app/staging"), "curate.py did not create /app/staging."
    actual_entries = set(os.listdir("/app/staging"))
    expected_entries = {clean_1, clean_2}
    assert actual_entries == expected_entries, (
        f"Incorrect staging contents. Expected {sorted(expected_entries)}, got {sorted(actual_entries)}."
    )
    for name in expected_entries:
        path = os.path.join("/app/staging", name)
        assert os.path.isfile(path) and not os.path.islink(path), f"Clean artifact {name} was not preserved as a regular file."
        with open(path, "rb") as f:
            assert f.read() == files[name], f"Clean artifact {name} was modified."

    assert os.path.isfile("/app/logs/packer_out.log"), "Packer stdout log was not created."
    with open("/app/logs/packer_out.log", "rb") as f:
        log_data = f.read()
    assert marker.encode() in log_data, "The packer's stdout was not redirected to /app/logs/packer_out.log."

    expected_output = bytearray()
    for name in sorted(expected_entries):
        data = files[name]
        header = f"{name[:32].ljust(32)}{str(len(data)).ljust(32)}"
        expected_output.extend(header.encode("utf-8"))
        expected_output.extend(data)

    assert os.path.isfile("/app/final_artifact.pck"), "The final artifact was not generated by the workflow."
    with open("/app/final_artifact.pck", "rb") as f:
        actual_output = f.read()
    assert actual_output == bytes(expected_output), "The final artifact is not the packer's exact output for the curated staging directory."

    shutil.rmtree(work, ignore_errors=True)


def test_final_artifact_size():
    target_file = "/app/final_artifact.pck"
    assert os.path.exists(target_file), f"Final artifact {target_file} was not generated."

    size = os.path.getsize(target_file)
    threshold = 5000000
    assert size < threshold, f"Final artifact size {size} bytes exceeds the threshold of {threshold} bytes. The packer likely included vulnerable/deprecated files or fell into a symlink loop."


def test_packer_out_log_exists():
    log_path = "/app/logs/packer_out.log"
    assert os.path.exists(log_path), f"Packer stdout log {log_path} was not created. Ensure you redirected stdout."
    assert os.path.isfile(log_path), f"{log_path} is not a file."


def test_staging_directory_exists():
    staging_dir = "/app/staging"
    assert os.path.exists(staging_dir), f"Staging directory {staging_dir} does not exist."
    assert os.path.isdir(staging_dir), f"{staging_dir} is not a directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
