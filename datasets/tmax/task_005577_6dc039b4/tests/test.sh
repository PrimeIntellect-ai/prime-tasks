#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import os
import secrets
import shutil
import stat
import struct
import subprocess
import time

SCRIPT = "/home/user/backup.py"
SRC = "/home/user/artifacts"
DST = "/home/user/backup_dest"
LOG = "/home/user/backup.log"


def get_version(path):
    with open(path, 'rb') as f:
        header = f.read(4)
        if header != b'ARTF':
            return None
        ver_bytes = f.read(4)
        return struct.unpack('<I', ver_bytes)[0]


# Preserve the original final-state assertions.
def test_backup_log_contents():
    assert os.path.isfile(LOG), f"Log file missing: {LOG}"

    with open(LOG, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 files to be logged, but found {len(lines)}: {lines}"

    expected_real_paths = {
        os.path.realpath("/home/user/artifacts/dirA/file_a.bin"),
        os.path.realpath("/home/user/artifacts/dirA/dirB/file_b.bin")
    }
    actual_real_paths = {os.path.realpath(p) for p in lines}
    assert actual_real_paths == expected_real_paths, (
        f"Logged paths do not resolve to the expected physical files.\n"
        f"Expected real paths: {expected_real_paths}\n"
        f"Actual real paths: {actual_real_paths}"
    )


def test_backup_dest_updated_files():
    with open(LOG, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    for src_path in lines:
        rel_path = os.path.relpath(src_path, SRC)
        dst_path = os.path.join(DST, rel_path)
        assert os.path.isfile(dst_path), f"Expected backed up file missing at: {dst_path}"
        src_ver = get_version(src_path)
        dst_ver = get_version(dst_path)
        assert dst_ver == src_ver, (
            f"Destination file version {dst_ver} does not match source version "
            f"{src_ver} for {dst_path}"
        )


def test_backup_dest_untouched_files():
    root_file = "/home/user/backup_dest/root_file.bin"
    assert os.path.isfile(root_file)
    assert get_version(root_file) == 2, "root_file.bin should not have been updated or altered"

    file_c = "/home/user/backup_dest/dirC/file_c.bin"
    assert os.path.isfile(file_c)
    assert get_version(file_c) == 6, "file_c.bin should not have been overwritten (dest had higher version)"


def test_invalid_file_ignored():
    invalid_dest = "/home/user/backup_dest/invalid.bin"
    assert not os.path.exists(invalid_dest), "invalid.bin should have been ignored due to missing ARTF header"


def test_no_extra_files_in_dest():
    bin_count = 0
    for root, dirs, files in os.walk(DST):
        for name in files:
            if name.endswith('.bin'):
                bin_count += 1
    assert bin_count == 4, f"Expected exactly 4 .bin files in backup_dest, found {bin_count}"


test_backup_log_contents()
test_backup_dest_updated_files()
test_backup_dest_untouched_files()
test_invalid_file_ignored()
test_no_extra_files_in_dest()

# The submitted artifact must exist as a regular file and be executable by Python.
assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"Not a regular file: {SCRIPT}"
compile(open(SCRIPT, 'rb').read(), SCRIPT, 'exec')

# Build a fresh, randomized fixture, then actually execute the submitted script.
token = secrets.token_hex(8)
external = f"/tmp/backup_external_{token}"
for path in (SRC, DST, external):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
if os.path.lexists(LOG):
    os.unlink(LOG)

os.makedirs(os.path.join(SRC, "primary", "nested"))
os.makedirs(DST)
os.makedirs(external)


def art(version, payload):
    return b'ARTF' + struct.pack('<I', version) + payload


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


base = secrets.randbelow(100000) + 100
update_name = f"update_{token}.bin"
equal_name = f"equal_{token}.bin"
older_name = f"older_{token}.bin"
new_name = f"new_{token}.bin"
external_name = f"external_{token}.bin"
invalid_name = f"invalid_{token}.bin"
short_name = f"short_{token}.bin"

update_src = art(base + 5, b"source-update-" + secrets.token_bytes(19))
update_old = art(base + 4, b"destination-old-" + secrets.token_bytes(17))
equal_src = art(base + 7, b"source-equal-" + secrets.token_bytes(13))
equal_dst = art(base + 7, b"destination-equal-must-stay-" + secrets.token_bytes(11))
older_src = art(base + 2, b"source-older-" + secrets.token_bytes(15))
older_dst = art(base + 9, b"destination-newer-must-stay-" + secrets.token_bytes(9))
new_src = art(base + 3, b"brand-new-" + secrets.token_bytes(23))
ext_src = art(base + 8, b"through-symlink-" + secrets.token_bytes(21))

put(os.path.join(SRC, "primary", update_name), update_src)
put(os.path.join(SRC, "primary", equal_name), equal_src)
put(os.path.join(SRC, "primary", older_name), older_src)
put(os.path.join(SRC, "primary", "nested", new_name), new_src)
put(os.path.join(SRC, "primary", invalid_name), b"BADF" + struct.pack('<I', base + 50) + b"invalid")
put(os.path.join(SRC, "primary", short_name), b"ARTF\x01\x02")
put(os.path.join(external, external_name), ext_src)

put(os.path.join(DST, "primary", update_name), update_old)
put(os.path.join(DST, "primary", equal_name), equal_dst)
put(os.path.join(DST, "primary", older_name), older_dst)

# Defeat modification-time backup logic: the higher-version source is older,
# while equal/older-version sources are newer than their destinations.
now = time.time()
os.utime(os.path.join(SRC, "primary", update_name), (now - 5000, now - 5000))
os.utime(os.path.join(DST, "primary", update_name), (now, now))
os.utime(os.path.join(SRC, "primary", equal_name), (now + 100, now + 100))
os.utime(os.path.join(SRC, "primary", older_name), (now + 100, now + 100))

# Two names reach one physical external directory; only one may be processed.
os.symlink(external, os.path.join(SRC, "alias_one"))
os.symlink(external, os.path.join(SRC, "alias_two"))
# Circular directory link must not cause recursion or duplicate processing.
os.symlink(SRC, os.path.join(SRC, "primary", "back_to_root"))

result = subprocess.run(
    ["python3", SCRIPT],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=10,
)
assert result.returncode == 0, (
    f"backup.py exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
)
assert os.path.isfile(LOG), "backup.py did not create /home/user/backup.log"

with open(LOG, 'r') as f:
    lines = [line.rstrip('\n') for line in f if line.rstrip('\n')]

update_path = os.path.join(SRC, "primary", update_name)
new_path = os.path.join(SRC, "primary", "nested", new_name)
ext_candidates = {
    os.path.join(SRC, "alias_one", external_name),
    os.path.join(SRC, "alias_two", external_name),
}
ext_logged = [p for p in lines if p in ext_candidates]
assert len(ext_logged) == 1, f"Physical symlinked directory was not processed exactly once: {lines}"
assert len(lines) == 3, f"Expected exactly three successful copies, got: {lines}"
assert set(lines) == {update_path, new_path, ext_logged[0]}, f"Incorrect log contents: {lines}"
assert all(os.path.isabs(p) for p in lines), f"Log contains a non-absolute source path: {lines}"

# Every copied destination must preserve its traversed relative path and exact bytes.
for source_path in lines:
    relative = os.path.relpath(source_path, SRC)
    destination_path = os.path.join(DST, relative)
    assert os.path.isfile(destination_path), f"Missing copied file: {destination_path}"
    with open(source_path, 'rb') as sf, open(destination_path, 'rb') as df:
        assert df.read() == sf.read(), f"Copied bytes differ for {destination_path}"

with open(os.path.join(DST, "primary", update_name), 'rb') as f:
    assert f.read() == update_src, "Higher-version source was not copied exactly"
with open(os.path.join(DST, "primary", equal_name), 'rb') as f:
    assert f.read() == equal_dst, "Equal-version destination was altered"
with open(os.path.join(DST, "primary", older_name), 'rb') as f:
    assert f.read() == older_dst, "Newer-version destination was altered"

assert not os.path.exists(os.path.join(DST, "primary", invalid_name)), "Invalid magic file was copied"
assert not os.path.exists(os.path.join(DST, "primary", short_name)), "Truncated header file was copied"
assert sum(os.path.exists(os.path.join(DST, alias, external_name)) for alias in ("alias_one", "alias_two")) == 1, \
    "The same physical symlinked directory was copied more than once"

actual_files = set()
for root, dirs, files in os.walk(DST):
    for name in files:
        actual_files.add(os.path.relpath(os.path.join(root, name), DST))
expected_files = {
    os.path.join("primary", update_name),
    os.path.join("primary", equal_name),
    os.path.join("primary", older_name),
    os.path.join("primary", "nested", new_name),
    os.path.relpath(os.path.join(DST, os.path.relpath(ext_logged[0], SRC)), DST),
}
assert actual_files == expected_files, f"Unexpected destination files: {actual_files ^ expected_files}"
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
