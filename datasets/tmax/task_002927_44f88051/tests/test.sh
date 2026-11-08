#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import shutil
import subprocess
import uuid


def test_script_exists_and_executable():
    script_path = "/home/user/process_backup.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_quarantine_log():
    log_path = "/home/user/quarantine.log"
    assert os.path.isfile(log_path), f"Quarantine log {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_malicious = [
        "../../../etc/shadow",
        "/var/log/syslog"
    ]

    assert lines == expected_malicious, f"Quarantine log contents incorrect. Expected {expected_malicious}, got {lines}."


def test_safe_extracted_files():
    base_dir = "/home/user/safe_restore"

    expected_files = {
        "system/info.txt": b"System is operational.\n",
        "web/index.html": b"<html>Hello</html>\n",
        "deep/nested/dir/config.json": b'{"key": "value"}\n',
        "safe_but_tricky..txt": b'".." is not "../"\n'
    }

    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(base_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected extracted file {full_path} does not exist."

        with open(full_path, "rb") as f:
            content = f.read()

        assert content == expected_content, f"Content of {full_path} is incorrect."


def test_restore_checksums():
    checksum_path = "/home/user/restore_checksums.txt"
    assert os.path.isfile(checksum_path), f"Checksum manifest {checksum_path} does not exist."

    expected_files = {
        "system/info.txt": b"System is operational.\n",
        "web/index.html": b"<html>Hello</html>\n",
        "deep/nested/dir/config.json": b'{"key": "value"}\n',
        "safe_but_tricky..txt": b'".." is not "../"\n'
    }

    expected_lines = []
    for rel_path, content in expected_files.items():
        sha256 = hashlib.sha256(content).hexdigest()
        expected_lines.append(f"{sha256}  {rel_path}")

    expected_lines.sort()

    with open(checksum_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, "Checksum manifest contents or sorting are incorrect."


def test_restore_status():
    status_path = "/home/user/restore_status.txt"
    assert os.path.isfile(status_path), f"Status file {status_path} does not exist."

    with open(status_path, "r") as f:
        content = f.read().strip()

    assert content == "EXTRACTION COMPLETE", f"Status file content incorrect. Expected 'EXTRACTION COMPLETE', got '{content}'."


def _install_command_probe(command, log_path):
    candidates = [shutil.which(command), f"/usr/bin/{command}", f"/bin/{command}"]
    installed = []
    seen = set()
    for candidate in candidates:
        if not candidate or not os.path.exists(candidate):
            continue
        target = os.path.realpath(candidate)
        if target in seen:
            continue
        seen.add(target)
        backup = target + ".verifier-real"
        if os.path.lexists(backup):
            os.unlink(backup)
        os.replace(target, backup)
        probe = f'''#!/usr/bin/python3
import json, os, sys
record = {{"cwd": os.getcwd(), "args": sys.argv[1:]}}
if {command!r} == "mv":
    record["source_exists"] = len(sys.argv) >= 3 and os.path.exists(sys.argv[-2])
    record["dest_exists"] = len(sys.argv) >= 2 and os.path.exists(sys.argv[-1])
with open({log_path!r}, "a") as out:
    out.write(json.dumps(record) + "\\n")
os.execv({backup!r}, [{backup!r}] + sys.argv[1:])
'''
        with open(target, "w") as f:
            f.write(probe)
        os.chmod(target, 0o755)
        installed.append((target, backup))
    return installed


def _restore_probes(installed):
    for target, backup in reversed(installed):
        if os.path.lexists(target):
            os.unlink(target)
        if os.path.exists(backup):
            os.replace(backup, target)


def _read_probe_log(path):
    if not os.path.exists(path):
        return []
    with open(path, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_script_processes_unseen_archive_and_uses_required_commands():
    token = uuid.uuid4().hex
    safe_files = {
        f"alpha_{token}.txt": ("first-" + token + "\n").encode(),
        f"nested_{token}/zeta.bin": os.urandom(37),
        f"nested_{token}/deeper/config.cfg": ("setting=" + token + "\n").encode(),
        f"tricky..name_{token}": b"ordinary safe name\n",
    }
    absolute_path = f"/tmp/verifier_absolute_escape_{token}"
    traversal_path = f"../verifier_parent_escape_{token}"
    substring_path = f"apparently_safe..//../blocked_{token}"
    malicious = [traversal_path, absolute_path, substring_path]

    entries = [
        (list(safe_files)[2], safe_files[list(safe_files)[2]]),
        (traversal_path, b"must not escape\n"),
        (list(safe_files)[0], safe_files[list(safe_files)[0]]),
        (absolute_path, b"must not be absolute\n"),
        (list(safe_files)[3], safe_files[list(safe_files)[3]]),
        (substring_path, b"substring must be rejected\n"),
        (list(safe_files)[1], safe_files[list(safe_files)[1]]),
    ]

    archive = bytearray()
    for path, content in entries:
        archive.extend(f"PATH: {path}\n".encode())
        archive.extend(b"B64DATA: " + base64.b64encode(content) + b"\n")

    shutil.rmtree("/home/user/safe_restore", ignore_errors=True)
    os.makedirs("/home/user/safe_restore", exist_ok=True)
    for path in [
        "/home/user/quarantine.log",
        "/home/user/restore_checksums.txt",
        "/home/user/restore_status.txt",
        absolute_path,
        f"/home/user/verifier_parent_escape_{token}",
    ]:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    with open("/home/user/incoming/backup.dat", "wb") as f:
        f.write(archive)

    sha_log = f"/tmp/sha256sum_probe_{token}.jsonl"
    mv_log = f"/tmp/mv_probe_{token}.jsonl"
    installed = []
    try:
        installed.extend(_install_command_probe("sha256sum", sha_log))
        installed.extend(_install_command_probe("mv", mv_log))
        result = subprocess.run(
            ["/home/user/process_backup.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    finally:
        _restore_probes(installed)

    assert result.returncode == 0, (
        f"Script failed on a valid unseen archive. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    actual_files = set()
    for root, dirs, files in os.walk("/home/user/safe_restore"):
        for name in files:
            actual_files.add(os.path.relpath(os.path.join(root, name), "/home/user/safe_restore"))
    assert actual_files == set(safe_files), f"Unexpected extracted file set: {actual_files}"
    for rel_path, expected in safe_files.items():
        with open(os.path.join("/home/user/safe_restore", rel_path), "rb") as f:
            assert f.read() == expected, f"Wrong decoded content for {rel_path}"

    assert not os.path.exists(absolute_path), "Absolute path was extracted"
    assert not os.path.exists(f"/home/user/verifier_parent_escape_{token}"), "Traversal path escaped restore directory"
    with open("/home/user/quarantine.log", "r") as f:
        assert f.read().splitlines() == malicious

    expected_manifest = [
        f"{hashlib.sha256(content).hexdigest()}  {path}"
        for path, content in sorted(safe_files.items())
    ]
    with open("/home/user/restore_checksums.txt", "r") as f:
        assert f.read().splitlines() == expected_manifest

    sha_calls = _read_probe_log(sha_log)
    assert sha_calls, "The script did not invoke the required sha256sum command"
    assert all(call["cwd"] == "/home/user/safe_restore" for call in sha_calls), (
        "sha256sum must be run from inside /home/user/safe_restore"
    )
    hashed_paths = set()
    for call in sha_calls:
        for arg in call["args"]:
            if arg.startswith("-"):
                continue
            resolved = os.path.normpath(os.path.join(call["cwd"], arg)) if not os.path.isabs(arg) else os.path.normpath(arg)
            if resolved.startswith("/home/user/safe_restore/"):
                hashed_paths.add(os.path.relpath(resolved, "/home/user/safe_restore"))
    assert set(safe_files).issubset(hashed_paths), "sha256sum was not invoked on every extracted file"

    with open("/home/user/restore_status.txt", "r") as f:
        assert f.read() == "EXTRACTION COMPLETE"
    mv_calls = _read_probe_log(mv_log)
    atomic_status_moves = [
        call for call in mv_calls
        if len(call["args"]) >= 2
        and os.path.normpath(call["args"][-1]) == "/home/user/restore_status.txt"
        and os.path.normpath(call["args"][-2]) != "/home/user/restore_status.txt"
        and call.get("source_exists")
        and not call.get("dest_exists")
    ]
    assert atomic_status_moves, "Status file was not atomically installed from an existing temporary file using mv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
