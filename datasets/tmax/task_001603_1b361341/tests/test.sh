#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

cat << 'STATIC_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_rejected_log():
    log_path = "/home/user/rejected.log"
    assert os.path.isfile(log_path), f"Rejected log missing at {log_path}"
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()
    assert len(content) == 1, f"Expected exactly 1 rejected path, found {len(content)}"
    assert content[0] == "../etc/hacked.sh", f"Expected '../etc/hacked.sh' in rejected.log, got '{content[0]}'"

def test_file_a_restored_and_processed():
    file_path = "/home/user/restored/file_a.txt"
    assert os.path.isfile(file_path), f"file_a.txt missing at {file_path}"
    with open(file_path, "rb") as f:
        raw_data = f.read()
    assert b"\r\n" not in raw_data, "file_a.txt still contains CRLF line endings"
    assert b"\xff\xfe" not in raw_data[:2], "file_a.txt still contains UTF-16 BOM"
    assert b"\x00" not in raw_data, "file_a.txt appears to still be UTF-16 encoded (contains null bytes)"
    try:
        text = raw_data.decode("utf-8-sig")
    except UnicodeDecodeError:
        pytest.fail("file_a.txt is not valid UTF-8")
    assert "SERVER_LEGACY" not in text, "file_a.txt still contains 'SERVER_LEGACY'"
    assert "SERVER_MODERN" in text, "file_a.txt missing 'SERVER_MODERN'"
    assert "System Data" in text, "file_a.txt missing 'System Data'"

def test_file_b_restored_and_processed():
    file_path = "/home/user/restored/dir/file_b.txt"
    assert os.path.isfile(file_path), f"dir/file_b.txt missing at {file_path}"
    with open(file_path, "rb") as f:
        raw_data = f.read()
    assert b"\r\n" not in raw_data, "dir/file_b.txt still contains CRLF line endings"
    try:
        text = raw_data.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("dir/file_b.txt is not valid UTF-8")
    assert "SERVER_LEGACY" not in text, "dir/file_b.txt still contains 'SERVER_LEGACY'"
    assert "SERVER_MODERN" in text, "dir/file_b.txt missing 'SERVER_MODERN'"
    assert "Start\nSERVER_MODERN\nEnd" in text, "dir/file_b.txt content does not match expected structure"

def test_malicious_file_not_extracted():
    assert not os.path.exists("/etc/hacked.sh"), "Malicious file was extracted to /etc/hacked.sh"
    assert not os.path.exists("/home/user/restored/etc/hacked.sh"), "Malicious file was extracted to /home/user/restored/etc/hacked.sh"
    assert not os.path.exists("/home/user/etc/hacked.sh"), "Malicious file was extracted to /home/user/etc/hacked.sh"
STATIC_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

test -f /home/user/processor.go
test ! -L /home/user/processor.go
test -s /home/user/processor.go

rm -rf /home/user/restored
mkdir -p /home/user/restored
rm -f /home/user/rejected.log

python3 << 'BUILD_EOF'
import io
import json
import os
import tarfile
import uuid

nonce = uuid.uuid4().hex
safe = {
    f"dynamic_{nonce}.txt": f"dynamic payload {nonce}\nSERVER_MODERN\n".encode("utf-8"),
    f"nested_{nonce}/second.txt": f"second payload {nonce}\n".encode("utf-8"),
}
traversal = f"../escape_{nonce}.txt"
absolute = f"/tmp/processor_guard_{nonce}.txt"
guards = {
    "/home/user/" + traversal[3:]: f"TRAVERSAL-GUARD-{nonce}\n".encode(),
    absolute: f"ABSOLUTE-GUARD-{nonce}\n".encode(),
}

for path, data in guards.items():
    with open(path, "wb") as f:
        f.write(data)

with tarfile.open("/home/user/backup.tar", "w") as tar:
    for name, data in safe.items():
        info = tarfile.TarInfo(name=name)
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))
    for name in (traversal, absolute):
        data = (f"MALICIOUS-{nonce}\n").encode()
        info = tarfile.TarInfo(name=name)
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))

with open("/tmp/processor_challenge.json", "w", encoding="utf-8") as f:
    json.dump({
        "safe": {k: v.decode("utf-8") for k, v in safe.items()},
        "rejected": [traversal, absolute],
        "guards": {k: v.decode("utf-8") for k, v in guards.items()},
    }, f)
BUILD_EOF

cd /home/user
timeout 60s go run /home/user/processor.go

python3 << 'DYNAMIC_EOF'
import json
import os

with open("/tmp/processor_challenge.json", encoding="utf-8") as f:
    challenge = json.load(f)

for archive_name, expected in challenge["safe"].items():
    path = os.path.join("/home/user/restored", archive_name)
    assert os.path.isfile(path), f"Dynamically named safe file was not extracted: {archive_name}"
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == expected.encode("utf-8"), f"Unexpected content for dynamically named safe file {archive_name}"

log_path = "/home/user/rejected.log"
assert os.path.isfile(log_path), "processor.go did not create rejected.log when executed"
with open(log_path, "r", encoding="utf-8") as f:
    rejected = f.read().splitlines()
assert len(rejected) == len(challenge["rejected"]), f"Expected exactly {len(challenge['rejected'])} dynamically rejected paths, got {rejected!r}"
assert set(rejected) == set(challenge["rejected"]), f"rejected.log does not contain the exact dynamic archive paths: {rejected!r}"

for path, expected in challenge["guards"].items():
    assert os.path.isfile(path), f"Guard file was removed by unsafe extraction: {path}"
    with open(path, "rb") as f:
        actual = f.read()
    assert actual == expected.encode("utf-8"), f"Malicious archive entry overwrote guard file {path}"

for rejected in challenge["rejected"]:
    if rejected.startswith("/"):
        continue
    escaped = os.path.abspath(os.path.join("/home/user/restored", rejected))
    assert not escaped.startswith("/home/user/restored/") or not os.path.exists(escaped) or escaped in challenge["guards"], "Traversal entry was extracted"
DYNAMIC_EOF

); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
