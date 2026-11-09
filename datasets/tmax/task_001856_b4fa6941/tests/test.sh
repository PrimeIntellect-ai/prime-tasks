#!/bin/bash
mkdir -p /logs/verifier

verify() {
    [ -f /home/user/processor.go ] || return 1
    [ ! -L /home/user/processor.go ] || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib

def test_processed_dir_exists():
    assert os.path.isdir("/home/user/processed_backups"), "Directory /home/user/processed_backups/ was not created."

def test_manifest_content():
    manifest_path = "/home/user/processed_backups/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    raw_dir = "/home/user/raw_backups"
    assert os.path.isdir(raw_dir), "Original raw_backups directory is missing."

    expected_lines = []
    files = sorted([f for f in os.listdir(raw_dir) if f.endswith('.dat')])

    for filename in files:
        filepath = os.path.join(raw_dir, filename)
        with open(filepath, "rb") as f:
            header = f.read(16)
            sha256_hex = hashlib.sha256(header).hexdigest()
            expected_lines.append(f"{filename} {sha256_hex}")

    expected_manifest = "\n".join(expected_lines) + "\n"

    with open(manifest_path, "r") as f:
        actual_manifest = f.read()

    assert actual_manifest.strip() == expected_manifest.strip(), "The contents of manifest.txt do not match the expected output."

def test_hard_links_and_inodes():
    processed_dir = "/home/user/processed_backups"

    file_a = os.path.join(processed_dir, "file_A.dat")
    file_b = os.path.join(processed_dir, "file_B.dat")
    file_c = os.path.join(processed_dir, "file_C.dat")
    file_d = os.path.join(processed_dir, "file_D.dat")

    for f in [file_a, file_b, file_c, file_d]:
        assert os.path.isfile(f), f"File {f} is missing from processed_backups."

    inode_a = os.stat(file_a).st_ino
    inode_b = os.stat(file_b).st_ino
    inode_c = os.stat(file_c).st_ino
    inode_d = os.stat(file_d).st_ino

    assert inode_a == inode_c, "file_C.dat is not a hard link to file_A.dat (inodes differ)."
    assert inode_a != inode_b, "file_A.dat and file_B.dat should not be hard linked."
    assert inode_a != inode_d, "file_A.dat and file_D.dat should not be hard linked."
    assert inode_b != inode_d, "file_B.dat and file_D.dat should not be hard linked."
    assert inode_b != inode_c, "file_B.dat and file_C.dat should not be hard linked."

def test_file_contents():
    raw_dir = "/home/user/raw_backups"
    processed_dir = "/home/user/processed_backups"

    for filename in ["file_A.dat", "file_B.dat", "file_D.dat"]:
        raw_path = os.path.join(raw_dir, filename)
        proc_path = os.path.join(processed_dir, filename)

        with open(raw_path, "rb") as f:
            raw_content = f.read()
        with open(proc_path, "rb") as f:
            proc_content = f.read()

        assert raw_content == proc_content, f"Content of {filename} in processed_backups does not match original."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    rm -f /tmp/processor-under-test
    go build -o /tmp/processor-under-test /home/user/processor.go || return 1
    [ -x /tmp/processor-under-test ] || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import ctypes
import hashlib
import os
import secrets
import shutil
import struct
import subprocess
import sys

raw_dir = "/home/user/raw_backups"
out_dir = "/home/user/processed_backups"
exe = sys.argv[1]

shutil.rmtree(raw_dir, ignore_errors=True)
shutil.rmtree(out_dir, ignore_errors=True)
os.makedirs(raw_dir)
os.makedirs(out_dir)

token = secrets.token_hex(8)
h1 = secrets.token_bytes(16)
h2 = secrets.token_bytes(16)
h3 = secrets.token_bytes(16)
while h2 == h1:
    h2 = secrets.token_bytes(16)
while h3 in (h1, h2):
    h3 = secrets.token_bytes(16)

entries = [
    (f"10_first_{token}.dat", h1, secrets.token_bytes(37)),
    (f"20_second_{token}.dat", h2, secrets.token_bytes(29)),
    (f"30_dup_first_{token}.dat", h1, secrets.token_bytes(43)),
    (f"40_third_{token}.dat", h3, secrets.token_bytes(31)),
    (f"50_dup_second_{token}.dat", h2, secrets.token_bytes(41)),
]

contents = {}
headers = {}
for name, header, body in entries:
    data = header + body
    contents[name] = data
    headers[name] = header
    with open(os.path.join(raw_dir, name), "wb") as f:
        f.write(data)

with open(os.path.join(raw_dir, f"15_ignore_{token}.txt"), "wb") as f:
    f.write(h1 + b"not a dat file")

libc = ctypes.CDLL(None, use_errno=True)
libc.inotify_init1.argtypes = [ctypes.c_int]
libc.inotify_init1.restype = ctypes.c_int
libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
libc.inotify_add_watch.restype = ctypes.c_int
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
assert fd >= 0, "Could not initialize inotify"
wd = libc.inotify_add_watch(fd, out_dir.encode(), IN_MOVED_FROM | IN_MOVED_TO)
assert wd >= 0, "Could not watch processed_backups"

try:
    result = subprocess.run([exe], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, (
        "Compiled processor failed on generated inputs:\n" +
        result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")
    )

    events = []
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset < len(data):
            ev_wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            name = data[offset:offset + name_len].split(b"\0", 1)[0].decode(errors="replace")
            offset += name_len
            events.append((mask, cookie, name))
finally:
    os.close(fd)

names = sorted(contents)
expected_manifest = "\n".join(
    f"{name} {hashlib.sha256(headers[name]).hexdigest()}" for name in names
) + "\n"
manifest = os.path.join(out_dir, "manifest.txt")
assert os.path.isfile(manifest), "Generated run did not create manifest.txt"
with open(manifest, "r", encoding="utf-8") as f:
    assert f.read().strip() == expected_manifest.strip(), "Generated manifest is incorrect"

assert sorted(os.listdir(out_dir)) == sorted(names + ["manifest.txt"]), (
    "Output contains missing, extra, non-.dat, or leftover temporary files"
)

first_for_header = {}
representative_inode = {}
for name in names:
    header = headers[name]
    if header not in first_for_header:
        first_for_header[header] = name
    representative = first_for_header[header]
    output_path = os.path.join(out_dir, name)
    assert os.path.isfile(output_path), f"Missing generated output {name}"
    with open(output_path, "rb") as f:
        assert f.read() == contents[representative], f"Incorrect content for {name}"
    inode = (os.stat(output_path).st_dev, os.stat(output_path).st_ino)
    if header in representative_inode:
        assert inode == representative_inode[header], f"{name} is not linked to its first matching header"
    else:
        representative_inode[header] = inode

assert len(set(representative_inode.values())) == len(representative_inode), (
    "Files with different headers were hard linked"
)

moves_from = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM}
moves_to_manifest = [cookie for mask, cookie, name in events
                     if (mask & IN_MOVED_TO) and name == "manifest.txt"]
assert any(any(cookie == c and source != "manifest.txt" for c, source in moves_from)
           for cookie in moves_to_manifest), (
    "manifest.txt was not atomically renamed from a temporary file in processed_backups"
)
DYNAMIC_EOF

    python3 /tmp/test_dynamic.py /tmp/processor-under-test || return 1
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
