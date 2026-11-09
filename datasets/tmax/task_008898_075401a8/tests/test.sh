#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_config_extractor.py
import collections
import fcntl
import io
import os
import secrets
import shutil
import stat
import subprocess
import tarfile
import time
import zipfile

CONFIGS_DIR = "/home/user/configs"
WAL_FILE = "/home/user/config.wal"
GO_FILE = "/home/user/config_extractor.go"
INPUT_FILE = "/home/user/incoming/update.tar.gz"
ESCAPED_FILE = "/home/user/escaped.conf"
BINARY = "/tmp/config_extractor_submission"


def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def reset_outputs(extra_paths=()):
    remove_path(CONFIGS_DIR)
    os.makedirs(CONFIGS_DIR, exist_ok=True)
    remove_path(WAL_FILE)
    remove_path(ESCAPED_FILE)
    for path in extra_paths:
        remove_path(path)


def run_binary(timeout=15):
    result = subprocess.run(
        [BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Extractor exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def wal_lines():
    assert os.path.isfile(WAL_FILE), f"WAL file {WAL_FILE} is missing."
    with open(WAL_FILE, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


# Retain the original source assertions and require that the submitted program compiles.
assert os.path.isfile(GO_FILE), f"Go source file {GO_FILE} is missing."
with open(GO_FILE, "r", encoding="utf-8") as f:
    source = f.read()
assert "syscall.Flock" in source, "Go program does not seem to use syscall.Flock."
assert "syscall.LOCK_EX" in source, "Go program does not seem to use syscall.LOCK_EX."

build = subprocess.run(
    ["go", "build", "-o", BINARY, GO_FILE],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
)
assert build.returncode == 0, f"Go program did not compile:\n{build.stderr}"

# Re-run the submission from a clean state against the supplied archive.
reset_outputs()
run_binary()

# Original final-state assertions.
assert os.path.isdir(CONFIGS_DIR), f"{CONFIGS_DIR} directory is missing."
expected_files = ["app.conf", "db.conf", "safe_in_malicious.conf"]
for name in expected_files:
    path = os.path.join(CONFIGS_DIR, name)
    assert os.path.isfile(path), f"Expected safe file {name} was not extracted to {CONFIGS_DIR}."
assert not os.path.exists(os.path.join(CONFIGS_DIR, "escaped.conf")), (
    f"Malicious file was extracted to {os.path.join(CONFIGS_DIR, 'escaped.conf')}."
)
assert not os.path.exists(ESCAPED_FILE), f"Zip slip vulnerability exploited! File found at {ESCAPED_FILE}."

initial_lines = wal_lines()
expected_entries = [
    "ENTRY: app.conf | STATUS: EXTRACTED",
    "ENTRY: db.conf | STATUS: EXTRACTED",
    "ENTRY: ../../user/escaped.conf | STATUS: SLIP_DETECTED",
    "ENTRY: safe_in_malicious.conf | STATUS: EXTRACTED",
]
initial_content = "\n".join(initial_lines)
for entry in expected_entries:
    assert entry in initial_content, f"Expected WAL entry not found: '{entry}'"

# Also verify the supplied files' actual contents and that every supplied entry was logged once.
assert open(os.path.join(CONFIGS_DIR, "app.conf"), "rb").read() == b"port=8080\n"
assert open(os.path.join(CONFIGS_DIR, "db.conf"), "rb").read() == b"host=localhost\n"
assert open(os.path.join(CONFIGS_DIR, "safe_in_malicious.conf"), "rb").read() == b"safe payload"
assert collections.Counter(initial_lines) == collections.Counter(expected_entries), (
    f"Unexpected WAL contents for supplied archive: {initial_lines!r}"
)

# Generate a fresh archive with unpredictable names and contents so fixed files/WAL text cannot pass.
nonce = secrets.token_hex(8)
safe_name = f"service-{nonce}.conf"
nested_name = f"nested-{nonce}/database.conf"
outside_name = f"outside-{nonce}.conf"
prefix_dir = f"configs_evil_{nonce}"
prefix_raw = f"../{prefix_dir}/owned.conf"
absolute_path = f"/home/user/absolute-{nonce}.conf"
traversal_raw = f"../../user/{outside_name}"
link_name = f"unsafe-link-{nonce}"
link_target = f"../{outside_name}"
safe_payload = secrets.token_bytes(31)
nested_payload = secrets.token_bytes(29)

zip_one = io.BytesIO()
with zipfile.ZipFile(zip_one, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(safe_name, safe_payload)
    zf.writestr(nested_name, nested_payload)
    zf.writestr(traversal_raw, b"traversal payload")

zip_two = io.BytesIO()
with zipfile.ZipFile(zip_two, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(prefix_raw, b"prefix escape")
    zf.writestr(absolute_path, b"absolute escape")
    link = zipfile.ZipInfo(link_name)
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    zf.writestr(link, link_target)

with tarfile.open(INPUT_FILE, "w:gz") as tf:
    for member_name, data in ((f"first-{nonce}.zip", zip_one.getvalue()),
                              (f"second-{nonce}.zip", zip_two.getvalue())):
        info = tarfile.TarInfo(member_name)
        info.size = len(data)
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(data))

outside_path = f"/home/user/{outside_name}"
prefix_path = f"/home/user/{prefix_dir}"
absolute_output = absolute_path
reset_outputs((outside_path, prefix_path, absolute_output))

# Hold an exclusive lock before execution. A real per-entry Flock on the WAL must block
# the extractor without allowing an unlocked WAL write.
lock_file = open(WAL_FILE, "w+b")
fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
proc = subprocess.Popen([BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    time.sleep(0.8)
    assert proc.poll() is None, "Extractor completed while another process held the WAL lock."
    assert os.path.getsize(WAL_FILE) == 0, "Extractor wrote to the WAL without obtaining its lock."
finally:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()

try:
    stdout, stderr = proc.communicate(timeout=15)
except subprocess.TimeoutExpired:
    proc.kill()
    stdout, stderr = proc.communicate()
    raise AssertionError("Extractor did not finish after the WAL lock was released.")
assert proc.returncode == 0, (
    f"Extractor failed on generated archive with {proc.returncode}.\nstdout:\n{stdout}\nstderr:\n{stderr}"
)

# Validate generated safe contents and all escape cases, including an escaping symlink.
safe_path = os.path.join(CONFIGS_DIR, safe_name)
nested_path = os.path.join(CONFIGS_DIR, nested_name)
assert os.path.isfile(safe_path), f"Generated safe file was not extracted: {safe_name}"
assert os.path.isfile(nested_path), f"Generated nested safe file was not extracted: {nested_name}"
assert open(safe_path, "rb").read() == safe_payload, "Generated safe file content was changed."
assert open(nested_path, "rb").read() == nested_payload, "Generated nested file content was changed."
assert not os.path.lexists(os.path.join(CONFIGS_DIR, link_name)), "Escaping symlink was extracted."
assert not os.path.lexists(outside_path), "Traversal or symlink escaped the configs directory."
assert not os.path.lexists(prefix_path), "Prefix-confusion path escaped the configs directory."
assert not os.path.lexists(absolute_output), "Absolute ZIP path was extracted."

expected_dynamic = [
    f"ENTRY: {safe_name} | STATUS: EXTRACTED",
    f"ENTRY: {nested_name} | STATUS: EXTRACTED",
    f"ENTRY: {traversal_raw} | STATUS: SLIP_DETECTED",
    f"ENTRY: {prefix_raw} | STATUS: SLIP_DETECTED",
    f"ENTRY: {absolute_path} | STATUS: SLIP_DETECTED",
    f"ENTRY: {link_name} | STATUS: SLIP_DETECTED",
]
dynamic_lines = wal_lines()
assert collections.Counter(dynamic_lines) == collections.Counter(expected_dynamic), (
    f"Generated archive was not logged exactly once per entry. Expected {expected_dynamic!r}, got {dynamic_lines!r}"
)
PY_EOF

if python3 /tmp/test_config_extractor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
