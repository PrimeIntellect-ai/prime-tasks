#!/bin/bash
mkdir -p /logs/verifier
printf '0\n' > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import pytest

def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def test_script_exists_and_executable():
    script_path = "/home/user/curator.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_repo_structure_exists():
    assert os.path.isdir("/home/user/repo/artifacts"), "/home/user/repo/artifacts directory does not exist."
    assert os.path.isfile("/home/user/repo/manifest.json"), "/home/user/repo/manifest.json does not exist."

def test_manifest_contents_and_sharded_files():
    manifest_path = "/home/user/repo/manifest.json"
    try:
        with open(manifest_path, "r") as f:
            manifest = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{manifest_path} is not a valid JSON file.")

    assert isinstance(manifest, list), "Manifest should be a JSON array."
    assert len(manifest) == 2, f"Manifest should contain exactly 2 valid artifacts, found {len(manifest)}."

    incoming_dir = "/home/user/incoming"
    valid_files = {
        "alpha-tool.tar.gz": {"name": "alpha-tool", "version": "1.0.0", "type": "binary", "status": "release"},
        "beta-tool.zip": {"name": "beta-tool", "version": "2.1.0", "type": "binary", "status": "release"}
    }

    manifest_dict = {item.get("name"): item for item in manifest}

    for filename, expected_metadata in valid_files.items():
        filepath = os.path.join(incoming_dir, filename)
        assert os.path.isfile(filepath), f"Original file {filepath} is missing."

        file_hash = get_sha256(filepath)
        shard_dir = file_hash[:2]
        ext = ".tar.gz" if filename.endswith(".tar.gz") else ".zip"

        repo_filepath = os.path.join("/home/user/repo/artifacts", shard_dir, f"{file_hash}{ext}")
        assert os.path.isfile(repo_filepath), f"Artifact not found at expected sharded path: {repo_filepath}"

        repo_file_hash = get_sha256(repo_filepath)
        assert repo_file_hash == file_hash, f"Hash mismatch for {repo_filepath}"

        tool_name = expected_metadata["name"]
        assert tool_name in manifest_dict, f"{tool_name} is missing from the manifest."

        manifest_item = manifest_dict[tool_name]
        assert manifest_item.get("sha256") == file_hash, f"Manifest sha256 for {tool_name} does not match."
        assert manifest_item.get("type") == "binary", f"Manifest type for {tool_name} is incorrect."
        assert manifest_item.get("status") == "release", f"Manifest status for {tool_name} is incorrect."

def test_invalid_artifacts_not_in_repo():
    incoming_dir = "/home/user/incoming"
    invalid_files = ["gamma-source.tar.gz", "delta-tool.zip"]

    for filename in invalid_files:
        filepath = os.path.join(incoming_dir, filename)
        if os.path.isfile(filepath):
            file_hash = get_sha256(filepath)
            shard_dir = file_hash[:2]
            ext = ".tar.gz" if filename.endswith(".tar.gz") else ".zip"
            repo_filepath = os.path.join("/home/user/repo/artifacts", shard_dir, f"{file_hash}{ext}")
            assert not os.path.isfile(repo_filepath), f"Invalid artifact {filename} should not be in the repository."
TEST_EOF

mkdir -p /tmp/curator-test-bin
cat << 'EOF' > /tmp/curator-test-bin/tar
#!/bin/bash
extract=0
stdout=0
for arg in "$@"; do
    case "$arg" in
        --extract|-x|-[^-]*x*) extract=1 ;;
    esac
    case "$arg" in
        --to-stdout|-O|-[^-]*O*) stdout=1 ;;
    esac
done
if [ "$extract" -eq 1 ] && [ "$stdout" -ne 1 ]; then
    echo "non-streaming tar extraction denied: $*" >> /tmp/curator-denied.log
    exit 97
fi
exec /usr/bin/tar "$@"
EOF
cat << 'EOF' > /tmp/curator-test-bin/unzip
#!/bin/bash
stream=0
listing=0
for arg in "$@"; do
    case "$arg" in
        -p|-*p*) stream=1 ;;
        -l|-Z|-Z*) listing=1 ;;
    esac
done
if [ "$stream" -ne 1 ] && [ "$listing" -ne 1 ]; then
    echo "non-streaming unzip extraction denied: $*" >> /tmp/curator-denied.log
    exit 97
fi
exec /usr/bin/unzip "$@"
EOF
chmod +x /tmp/curator-test-bin/tar /tmp/curator-test-bin/unzip
rm -f /tmp/curator-denied.log

cat << 'PY_EOF' > /tmp/test_dynamic_curator.py
import ctypes
import errno
import hashlib
import io
import json
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
import time
import zipfile

SCRIPT = "/home/user/curator.sh"
INCOMING = "/home/user/incoming"
REPO = "/home/user/repo"

assert os.path.isfile(SCRIPT), "curator.sh is missing"
assert os.access(SCRIPT, os.X_OK), "curator.sh is not executable"

shutil.rmtree(INCOMING, ignore_errors=True)
shutil.rmtree(REPO, ignore_errors=True)
os.makedirs(INCOMING)
os.makedirs(os.path.join(REPO, "artifacts"))
with open(os.path.join(REPO, "manifest.json"), "w") as f:
    json.dump([], f)

nonce = secrets.token_hex(12)
sentinels = [f"extracted-sentinel-{nonce}-{i}.bin" for i in range(4)]
fixtures = [
    (f"runtime-alpha-{nonce}.tar.gz", {
        "name": f"runtime-alpha-{nonce}", "version": "7.3.1",
        "type": "binary", "status": "release", "nonce": nonce,
        "details": {"channel": "stable", "sequence": 17}
    }, sentinels[0]),
    (f"runtime-beta-{nonce}.zip", {
        "name": f"runtime-beta-{nonce}", "version": "8.4.2",
        "type": "binary", "status": "release", "nonce": nonce,
        "details": {"channel": "stable", "sequence": 29}
    }, sentinels[1]),
    (f"runtime-source-{nonce}.tar.gz", {
        "name": f"runtime-source-{nonce}", "version": "1.2.3",
        "type": "source", "status": "release", "nonce": nonce
    }, sentinels[2]),
    (f"runtime-beta-status-{nonce}.zip", {
        "name": f"runtime-beta-status-{nonce}", "version": "4.5.6",
        "type": "binary", "status": "beta", "nonce": nonce
    }, sentinels[3]),
]

def add_tar(path, metadata, sentinel):
    with tarfile.open(path, "w:gz") as tf:
        raw = json.dumps(metadata, separators=(",", ":")).encode()
        info = tarfile.TarInfo("metadata.json")
        info.size = len(raw)
        tf.addfile(info, io.BytesIO(raw))
        payload = ("payload-" + nonce).encode()
        info = tarfile.TarInfo(sentinel)
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))

def add_zip(path, metadata, sentinel):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("metadata.json", json.dumps(metadata, separators=(",", ":")))
        zf.writestr(sentinel, "payload-" + nonce)

for filename, metadata, sentinel in fixtures:
    path = os.path.join(INCOMING, filename)
    if filename.endswith(".tar.gz"):
        add_tar(path, metadata, sentinel)
    else:
        add_zip(path, metadata, sentinel)

# Watch the repository directory for same-directory rename pairs. An atomic
# temp-file replacement produces MOVED_FROM(temp) followed by MOVED_TO(manifest).
libc = ctypes.CDLL(None, use_errno=True)
fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
assert fd >= 0, "could not initialize inotify"
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
wd = libc.inotify_add_watch(fd, REPO.encode(), IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE)
assert wd >= 0, "could not watch repository"

env = os.environ.copy()
env["PATH"] = "/tmp/curator-test-bin:" + env.get("PATH", "")
env["HOME"] = "/home/user"
try:
    result = subprocess.run([SCRIPT], cwd="/home/user", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
except subprocess.TimeoutExpired as exc:
    raise AssertionError("curator.sh did not terminate") from exc

time.sleep(0.15)
events = []
while True:
    try:
        block = os.read(fd, 65536)
    except BlockingIOError:
        break
    if not block:
        break
    offset = 0
    while offset < len(block):
        watch, mask, cookie, length = struct.unpack_from("iIII", block, offset)
        offset += 16
        raw_name = block[offset:offset + length]
        offset += length
        name = raw_name.split(b"\0", 1)[0].decode(errors="replace")
        events.append((mask, cookie, name))
os.close(fd)

assert result.returncode == 0, (
    f"curator.sh failed with status {result.returncode}\n"
    f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
)
assert not os.path.exists("/tmp/curator-denied.log"), \
    "curator.sh attempted to extract an archive instead of streaming metadata"

manifest_path = os.path.join(REPO, "manifest.json")
assert os.path.isfile(manifest_path), "manifest.json was not created"
with open(manifest_path) as f:
    manifest = json.load(f)
assert isinstance(manifest, list), "manifest.json is not a JSON array"

valid = fixtures[:2]
assert len(manifest) == len(valid), \
    f"dynamic manifest should contain exactly {len(valid)} valid artifacts"
by_name = {item.get("name"): item for item in manifest if isinstance(item, dict)}
expected_repo_files = set()
for filename, metadata, sentinel in valid:
    source = os.path.join(INCOMING, filename)
    digest = hashlib.sha256(open(source, "rb").read()).hexdigest()
    expected = dict(metadata)
    expected["sha256"] = digest
    assert by_name.get(metadata["name"]) == expected, \
        f"incorrect streamed metadata for {filename}"
    ext = ".tar.gz" if filename.endswith(".tar.gz") else ".zip"
    destination = os.path.join(REPO, "artifacts", digest[:2], digest + ext)
    assert os.path.isfile(destination), f"missing sharded artifact for {filename}"
    assert hashlib.sha256(open(destination, "rb").read()).hexdigest() == digest, \
        f"repository copy differs from {filename}"
    expected_repo_files.add(os.path.realpath(destination))

for filename, metadata, sentinel in fixtures[2:]:
    source = os.path.join(INCOMING, filename)
    digest = hashlib.sha256(open(source, "rb").read()).hexdigest()
    ext = ".tar.gz" if filename.endswith(".tar.gz") else ".zip"
    destination = os.path.join(REPO, "artifacts", digest[:2], digest + ext)
    assert not os.path.exists(destination), f"invalid artifact {filename} was accepted"
    assert metadata["name"] not in by_name, f"invalid artifact {filename} is in manifest"

actual_repo_files = set()
for root, dirs, files in os.walk(os.path.join(REPO, "artifacts")):
    for name in files:
        actual_repo_files.add(os.path.realpath(os.path.join(root, name)))
assert actual_repo_files == expected_repo_files, "unexpected files exist in the artifact store"

for root in ("/home/user", "/tmp"):
    for current, dirs, files in os.walk(root):
        for sentinel in sentinels:
            assert sentinel not in files, \
                f"archive payload {sentinel} was extracted to disk"

moved_from = {(cookie, name) for mask, cookie, name in events
              if mask & IN_MOVED_FROM and cookie and name != "manifest.json"}
atomic_replacements = 0
for mask, cookie, name in events:
    if mask & IN_MOVED_TO and name == "manifest.json" and cookie:
        if any(old_cookie == cookie for old_cookie, old_name in moved_from):
            atomic_replacements += 1
assert atomic_replacements >= len(valid), (
    "manifest.json was not atomically replaced from a temporary file in the "
    "repository for each valid artifact"
)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_dynamic_curator.py 2>&1; then
    printf '1\n' > /logs/verifier/reward.txt
fi
