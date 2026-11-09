#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import secrets
import struct
import subprocess
import sys
import tempfile
import zipfile

import pytest

SCRIPT_PATH = "/home/user/index_docs.py"
INDEX_PATH = "/home/user/doc_index.jsonl"


def test_script_exists_and_uses_flock():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "fcntl" in content and "flock" in content, "The script must use fcntl.flock for exclusive file locking."


def test_zip_slip_not_extracted():
    hacked_file = "/home/user/hacked.txt"
    assert not os.path.exists(hacked_file), "Zip slip vulnerability triggered! Malicious file was extracted."


def test_doc_index_jsonl_content():
    assert os.path.isfile(INDEX_PATH), f"Output file {INDEX_PATH} does not exist."

    parsed_lines = []
    with open(INDEX_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    parsed_lines.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {INDEX_PATH}: {line}")

    assert len(parsed_lines) == 2, f"Expected 2 lines in {INDEX_PATH}, found {len(parsed_lines)}"

    results = {item.get("archive"): item for item in parsed_lines}

    assert "release_v1.zip" in results, "Missing entry for release_v1.zip"
    assert "release_v2.zip" in results, "Missing entry for release_v2.zip"

    v1_data = results["release_v1.zip"]
    assert "elf_entry_points" in v1_data, "Missing elf_entry_points in release_v1.zip entry"
    assert "firmware_main.elf" in v1_data["elf_entry_points"], "Missing firmware_main.elf entry point"
    v1_elf = v1_data["elf_entry_points"]["firmware_main.elf"]
    assert int(v1_elf, 16) == 0x400080, f"Incorrect entry point for firmware_main.elf: {v1_elf}"

    assert "gcode_machines" in v1_data, "Missing gcode_machines in release_v1.zip entry"
    assert "case_part.gcode" in v1_data["gcode_machines"], "Missing case_part.gcode machine name"
    assert v1_data["gcode_machines"]["case_part.gcode"] == "Prusa i3 MK3S", "Incorrect machine name for case_part.gcode"

    v2_data = results["release_v2.zip"]
    assert "elf_entry_points" in v2_data, "Missing elf_entry_points in release_v2.zip entry"
    assert "bootloader.elf" in v2_data["elf_entry_points"], "Missing bootloader.elf entry point"
    v2_elf = v2_data["elf_entry_points"]["bootloader.elf"]
    assert int(v2_elf, 16) == 0x08000000, f"Incorrect entry point for bootloader.elf: {v2_elf}"

    assert "gcode_machines" in v2_data, "Missing gcode_machines in release_v2.zip entry"
    assert "jig.gcode" in v2_data["gcode_machines"], "Missing jig.gcode machine name"
    assert v2_data["gcode_machines"]["jig.gcode"] == "Ender 3 Pro", "Incorrect machine name for jig.gcode"


def make_elf(entry_point):
    data = bytearray(64)
    data[0:4] = b"\x7fELF"
    data[4] = 2
    data[5] = 1
    data[24:32] = struct.pack("<Q", entry_point)
    return bytes(data)


def test_script_executes_on_dynamic_archives_concurrently_and_locks_output():
    original = None
    if os.path.exists(INDEX_PATH):
        with open(INDEX_PATH, "rb") as f:
            original = f.read()

    token = secrets.token_hex(10)
    slip_target = f"/home/user/runtime_zip_slip_{token}.txt"

    with tempfile.TemporaryDirectory(prefix="index-verifier-") as root:
        archives_dir = os.path.join(root, "archives")
        work_dir = os.path.join(root, "work")
        audit_dir = os.path.join(root, "audit")
        hook_dir = os.path.join(root, "hook")
        os.makedirs(archives_dir)
        os.makedirs(work_dir)
        os.makedirs(audit_dir)
        os.makedirs(hook_dir)

        # This verification-only import hook records successful flock calls and
        # the file descriptor target without changing flock's behavior.
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(r'''import fcntl, os
_original_flock = fcntl.flock
_audit_dir = os.environ.get("INDEX_FLOCK_AUDIT")
def _audited_flock(fd, operation):
    result = _original_flock(fd, operation)
    try:
        target = os.path.realpath("/proc/self/fd/%d" % fd)
        path = os.path.join(_audit_dir, "%d.log" % os.getpid())
        out = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(out, (str(operation) + "\t" + target + "\n").encode())
        finally:
            os.close(out)
    except Exception:
        pass
    return result
fcntl.flock = _audited_flock
''')

        expected = {}
        archive_paths = []
        count = 20
        for i in range(count):
            archive_name = f"dynamic_{token}_{i}_{secrets.token_hex(4)}.zip"
            archive_path = os.path.join(archives_dir, archive_name)
            elf_a = f"fw/{secrets.token_hex(4)}_{i}.elf"
            elf_b = f"nested/{secrets.token_hex(4)}_aux.elf"
            gcode = f"prints/{secrets.token_hex(4)}_{i}.gcode"
            entry_a = secrets.randbits(63) | 1
            entry_b = secrets.randbits(63) | 1
            machine = f"Machine-{secrets.token_hex(8)}-{i}"

            with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("docs/readme.md", "not indexable\n")
                zf.writestr(elf_a, make_elf(entry_a))
                zf.writestr(elf_b, make_elf(entry_b))
                zf.writestr(
                    gcode,
                    " ; TargetMachine: wrong-leading-space\n"
                    ";TargetMachine: wrong-prefix\n"
                    f"; TargetMachine: {machine}\n"
                    "; TargetMachine: ignored-second-value\nG28\n",
                )
                zf.writestr(f"../../home/user/runtime_zip_slip_{token}.txt", "do not extract")

            expected[archive_name] = {
                "archive": archive_name,
                "elf_entry_points": {elf_a: hex(entry_a), elf_b: hex(entry_b)},
                "gcode_machines": {gcode: machine},
            }
            archive_paths.append(archive_path)

        try:
            if os.path.exists(INDEX_PATH):
                os.unlink(INDEX_PATH)
            if os.path.exists(slip_target):
                os.unlink(slip_target)

            env = os.environ.copy()
            env["PYTHONPATH"] = hook_dir
            env["INDEX_FLOCK_AUDIT"] = audit_dir
            processes = [
                subprocess.Popen(
                    [sys.executable, SCRIPT_PATH, archive],
                    cwd=work_dir,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                for archive in archive_paths
            ]

            failures = []
            for archive, proc in zip(archive_paths, processes):
                stdout, stderr = proc.communicate(timeout=30)
                if proc.returncode != 0:
                    failures.append((os.path.basename(archive), proc.returncode, stdout, stderr))
            assert not failures, f"Script failed on generated archives: {failures}"

            assert os.path.isfile(INDEX_PATH), "Executing the script did not create doc_index.jsonl"
            parsed = []
            with open(INDEX_PATH, "r") as f:
                for number, line in enumerate(f, 1):
                    line = line.strip()
                    assert line, f"Blank or corrupted JSONL record at line {number}"
                    try:
                        parsed.append(json.loads(line))
                    except json.JSONDecodeError as exc:
                        pytest.fail(f"Concurrent output contains invalid JSON at line {number}: {exc}")

            assert len(parsed) == count, f"Expected {count} concurrent records, found {len(parsed)}"
            actual = {item.get("archive"): item for item in parsed}
            assert len(actual) == count, "Concurrent execution produced missing or duplicate archive records"
            assert actual == expected, "Generated ZIP metadata was not parsed correctly"

            audit_files = [os.path.join(audit_dir, name) for name in os.listdir(audit_dir)]
            assert len(audit_files) == count, "Not every script invocation called fcntl.flock"
            for path in audit_files:
                with open(path, "r") as f:
                    events = [line.rstrip("\n").split("\t", 1) for line in f if line.strip()]
                assert any(
                    (int(operation) & fcntl.LOCK_EX) and target == INDEX_PATH
                    for operation, target in events
                ), "The script did not acquire an exclusive flock on doc_index.jsonl"

            assert not os.path.exists(slip_target), "Zip slip vulnerability triggered during script execution"
            assert not any(os.scandir(work_dir)), "Archive members were extracted to disk instead of read from ZIP streams"
        finally:
            if original is None:
                if os.path.exists(INDEX_PATH):
                    os.unlink(INDEX_PATH)
            else:
                with open(INDEX_PATH, "wb") as f:
                    f.write(original)
            if os.path.exists(slip_target):
                os.unlink(slip_target)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
