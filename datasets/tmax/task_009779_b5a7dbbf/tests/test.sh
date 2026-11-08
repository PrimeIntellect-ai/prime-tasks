#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

python3 <<'PY' || status=1
import hashlib
import io
import json
import os
import re
import secrets
import shutil
import tarfile

storage = "/home/user/storage_dumps"
merged = "/home/user/merged_archives"
extracted = "/home/user/extracted_logs"

# Restore pristine inputs, then add an unpredictable recursive test archive.
shutil.rmtree(storage, ignore_errors=True)
os.makedirs(storage, exist_ok=True)
shutil.rmtree(merged, ignore_errors=True)
shutil.rmtree(extracted, ignore_errors=True)
for path in ("/home/user/unsafe_paths.log", "/home/user/critical_disk_errors.txt"):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

def tar_bytes(entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for name, content in entries:
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            tar.addfile(info, io.BytesIO(content))
    return buf.getvalue()

def split_into(data, directory, archive_name, chunk_size):
    os.makedirs(directory, exist_ok=True)
    for index, offset in enumerate(range(0, len(data), chunk_size), 1):
        with open(os.path.join(directory, f"{archive_name}.tar.part{index}"), "wb") as f:
            f.write(data[offset:offset + chunk_size])

log1 = b"""---
Timestamp: 2023-11-01T08:00:00Z
Severity: INFO
Message: System boot successful.
---
Timestamp: 2023-11-01T09:12:34Z
Severity: ERROR
Message: Disk space critical on /home
User intervention required.
---
Timestamp: 2023-11-01T10:00:00Z
Severity: WARNING
Message: High memory usage.
---
"""
log2 = b"""---
Timestamp: 2023-10-15T14:22:10Z
Severity: ERROR
Message: Disk space critical on /var/log
Purging old logs failed.
---
Timestamp: 2023-10-15T15:00:00Z
Severity: ERROR
Message: Network timeout reached.
---
"""

split_into(tar_bytes([
    ("../../../etc/shadow", b"root:$6$xyz:19000:0:99999:7:::"),
    ("logs/safe_log1.log", log1),
    ("/root/.ssh/authorized_keys", b"ssh-rsa AAAAB3N... hacker@evil"),
]), storage, "backup_A", 2048)

split_into(tar_bytes([
    ("logs/safe_log2.log", log2),
    ("../../var/backups/shadow.bak", b"root:$6$xyz..."),
    ("safe_directory/../../etc/passwd", b"root:x:0:0:root:/root:/bin/bash"),
]), storage, "backup_B", 2048)

token = secrets.token_hex(10)
canary_one = f"/tmp/archive_processor_canary_{token}_one"
canary_two = f"/tmp/archive_processor_canary_{token}_two"
sentinel_one = ("ORIGINAL-ONE-" + token).encode()
sentinel_two = ("ORIGINAL-TWO-" + token).encode()
with open(canary_one, "wb") as f:
    f.write(sentinel_one)
with open(canary_two, "wb") as f:
    f.write(sentinel_two)

second = secrets.randbelow(50) + 10
dynamic_early = f"2022-07-03T04:05:{second:02d}Z"
dynamic_late = f"2024-08-09T10:11:{second:02d}Z"
dynamic_log = f"""---
Timestamp: {dynamic_late}
Severity: ERROR
Message: Disk space critical on /srv/{token}
This continuation line must remain part of the message.
---
Timestamp: 2024-08-09T10:12:{second:02d}Z
Severity: WARNING
Message: Disk space critical but severity is not ERROR.
---
Timestamp: {dynamic_early}
Severity: ERROR
Message: Prefix: Disk space critical for randomized volume {token}
Further diagnostic detail.
---
Timestamp: 2024-08-09T10:13:{second:02d}Z
Severity: ERROR
Message: Disk Space Critical has the wrong case.
---
""".encode()

challenge_name = "recursive_" + token
challenge_dir = os.path.join(storage, "deep", "historical", token)
challenge_entries = [
    (f"logs/{token}/events.log", dynamic_log),
    (f"docs/{token}.txt", b"not a log"),
    (f"../../tmp/archive_processor_canary_{token}_one", b"COMPROMISED-ONE"),
    (canary_two, b"COMPROMISED-TWO"),
    (f"level/../../../outside_{token}", b"unsafe"),
]
split_into(tar_bytes(challenge_entries), challenge_dir, challenge_name, 700)

part_re = re.compile(r"^(?P<name>.+\.tar)\.part(?P<number>[0-9]+)$")
groups = {}
for root, _, files in os.walk(storage):
    for filename in files:
        match = part_re.match(filename)
        if match:
            groups.setdefault(match.group("name"), []).append(
                (int(match.group("number")), os.path.join(root, filename))
            )

def unsafe(name):
    if name.startswith("/"):
        return True
    depth = 0
    for component in name.split("/"):
        if component in ("", "."):
            continue
        if component == "..":
            if depth == 0:
                return True
            depth -= 1
        else:
            depth += 1
    return False

def matching_timestamps(text):
    result = []
    records = []
    current = []
    for line in text.splitlines():
        if line == "---":
            if current:
                records.append(current)
                current = []
        else:
            current.append(line)
    if current:
        records.append(current)

    for record in records:
        fields = {}
        active = None
        for line in record:
            match = re.match(r"^([^:]+):[ ]?(.*)$", line)
            if match:
                active = match.group(1)
                fields[active] = match.group(2)
            elif active is not None:
                fields[active] += "\n" + line
        if fields.get("Severity") == "ERROR" and "Disk space critical" in fields.get("Message", ""):
            result.append(fields.get("Timestamp", ""))
    return result

expected_unsafe = []
expected_timestamps = []
expected_merged = {}
for archive_name, parts in groups.items():
    data = b"".join(open(path, "rb").read() for _, path in sorted(parts))
    expected_merged[archive_name] = {
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    }
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as tar:
        for member in tar.getmembers():
            name = member.name
            if unsafe(name):
                expected_unsafe.append(name)
            elif member.isfile() and name.endswith(".log"):
                stream = tar.extractfile(member)
                if stream is not None:
                    expected_timestamps.extend(matching_timestamps(stream.read().decode("utf-8")))

expected = {
    "merged": expected_merged,
    "unsafe": sorted(expected_unsafe),
    "timestamps": sorted(expected_tibele for expected_tibele in expected_timestamps),
    "canaries": {
        canary_one: sentinel_one.decode(),
        canary_two: sentinel_two.decode(),
    },
    "challenge_archive": challenge_name + ".tar",
}
with open("/tmp/archive_processor_expected.json", "w") as f:
    json.dump(expected, f)
PY

if [ "$status" -eq 0 ]; then
    if [ ! -f /home/user/archive_processor/Cargo.toml ] || [ ! -f /home/user/archive_processor/src/main.rs ]; then
        echo "Rust Cargo project is missing" >&2
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    (
        cd /home/user/archive_processor &&
        timeout 180s cargo run --offline --quiet
    ) || status=1
fi

cat <<'PYTEST' > /tmp/test_final_state.py
import hashlib
import json
import os
import tarfile

with open("/tmp/archive_processor_expected.json") as f:
    EXPECTED = json.load(f)

def nonempty_lines(path):
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

def test_rust_project_exists():
    assert os.path.isfile("/home/user/archive_processor/Cargo.toml")
    assert os.path.isfile("/home/user/archive_processor/src/main.rs")

def test_merged_archives_directory_and_contents():
    merged_dir = "/home/user/merged_archives"
    assert os.path.isdir(merged_dir), f"Directory {merged_dir} does not exist."
    merged_files = os.listdir(merged_dir)
    assert any("backup_A" in f for f in merged_files), "backup_A.tar not found in merged_archives."
    assert any("backup_B" in f for f in merged_files), "backup_B.tar not found in merged_archives."
    assert EXPECTED["challenge_archive"] in merged_files, "Recursive randomized archive was not merged."

    for filename, metadata in EXPECTED["merged"].items():
        path = os.path.join(merged_dir, filename)
        assert os.path.isfile(path), f"Merged archive {filename} is missing."
        with open(path, "rb") as f:
            data = f.read()
        assert len(data) == metadata["size"], f"Merged archive {filename} has the wrong size."
        assert hashlib.sha256(data).hexdigest() == metadata["sha256"], f"Merged archive {filename} has incorrect bytes or part order."
        with tarfile.open(path, "r:") as tar:
            tar.getmembers()

def test_unsafe_paths_log():
    lines = nonempty_lines("/home/user/unsafe_paths.log")
    original_paths = {
        "../../../etc/shadow",
        "../../var/backups/shadow.bak",
        "/root/.ssh/authorized_keys",
        "safe_directory/../../etc/passwd",
    }
    assert original_paths.issubset(set(lines)), "One or more original unsafe paths were not reported."
    assert lines == EXPECTED["unsafe"], f"Unsafe paths are incorrect: {lines!r}"

def test_critical_disk_errors_txt():
    lines = nonempty_lines("/home/user/critical_disk_errors.txt")
    original_timestamps = {
        "2023-10-15T14:22:10Z",
        "2023-11-01T09:12:34Z",
    }
    assert original_timestamps.issubset(set(lines)), "One or more original critical errors were not reported."
    assert lines == EXPECTED["timestamps"], f"Critical disk errors are incorrect: {lines!r}"

def test_unsafe_entries_were_not_extracted():
    for path, sentinel in EXPECTED["canaries"].items():
        assert os.path.isfile(path), f"Canary {path} disappeared."
        with open(path, encoding="utf-8") as f:
            assert f.read() == sentinel, f"Unsafe archive entry overwrote {path}."
PYTEST

if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
