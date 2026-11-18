#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import errno
import os
import secrets
import stat
import struct
import subprocess
import tarfile

import pytest

HOME = "/home/user"
ROOT = HOME + "/config_tree"
LOG = HOME + "/broken_links.log"
TMP_ARCHIVE = HOME + "/config_backup.tar.gz.tmp"
ARCHIVE = HOME + "/config_backup.tar.gz"
STATE = {}


def write_file(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def snapshot_tree():
    result = {}

    def visit(directory, relative=""):
        with os.scandir(directory) as entries:
            for entry in entries:
                rel = os.path.join(relative, entry.name).replace(os.sep, "/")
                st = os.lstat(entry.path)
                if stat.S_ISDIR(st.st_mode):
                    result[rel] = ("dir", None)
                    visit(entry.path, rel)
                elif stat.S_ISLNK(st.st_mode):
                    result[rel] = ("symlink", os.readlink(entry.path))
                elif stat.S_ISREG(st.st_mode):
                    with open(entry.path, "rb") as f:
                        result[rel] = ("file", f.read())
                else:
                    result[rel] = ("other", stat.S_IFMT(st.st_mode))

    visit(ROOT)
    return result


def canonical_member(name):
    parts = [p for p in name.lstrip("/").split("/") if p not in ("", ".")]
    if "config_tree" in parts:
        parts = parts[parts.index("config_tree") + 1:]
    return "/".join(parts)


def start_inotify():
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, os.strerror(ctypes.get_errno())
    mask = 0x00000002 | 0x00000008 | 0x00000040 | 0x00000080 | 0x00000100
    wd = libc.inotify_add_watch(fd, HOME.encode(), mask)
    assert wd >= 0, os.strerror(ctypes.get_errno())
    return fd


def read_inotify(fd):
    data = bytearray()
    while True:
        try:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            data.extend(chunk)
        except BlockingIOError:
            break
        except OSError as e:
            if e.errno == errno.EAGAIN:
                break
            raise

    events = []
    offset = 0
    while offset + 16 <= len(data):
        wd, mask, cookie, length = struct.unpack_from("iIII", data, offset)
        offset += 16
        raw_name = bytes(data[offset:offset + length])
        offset += length
        name = raw_name.split(b"\0", 1)[0].decode(errors="surrogateescape")
        events.append((mask, cookie, name))
    return events


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_c_program():
    c_file = HOME + "/safe_backup.c"
    exe = HOME + "/safe_backup"
    assert os.path.isfile(c_file), f"Source file {c_file} is missing."

    compile_proc = subprocess.run(
        ["gcc", "-o", exe, c_file], capture_output=True, text=True
    )
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"

    subprocess.run(["rm", "-rf", ROOT], check=True)
    os.makedirs(ROOT + "/appA")
    os.makedirs(ROOT + "/appB")
    os.makedirs(ROOT + "/appC")

    write_file(ROOT + "/appA/config.ini", b"config data\n")
    write_file(ROOT + "/appC/data.bin", secrets.token_bytes(1024))
    os.symlink(ROOT + "/appA/config.ini", ROOT + "/appA/config_link.ini")
    os.symlink(ROOT + "/appB/loop2", ROOT + "/appB/loop1")
    os.symlink(ROOT + "/appB/loop1", ROOT + "/appB/loop2")
    os.symlink("loop_self", ROOT + "/appC/loop_self")

    token = secrets.token_hex(10)
    deep = f"generated_{token}/level1/level2/level3"
    pair_dir = f"generated_{token}/another/branch"
    os.makedirs(ROOT + "/" + deep)
    os.makedirs(ROOT + "/" + pair_dir)
    os.makedirs(ROOT + f"/generated_{token}/empty_directory")

    hidden_rel = deep + f"/.hidden_{secrets.token_hex(6)}"
    regular_rel = pair_dir + f"/settings_{secrets.token_hex(6)}.dat"
    valid_rel = deep + f"/valid_{secrets.token_hex(6)}"
    self_rel = deep + f"/cycle_{secrets.token_hex(6)}"
    pair1_rel = pair_dir + f"/first_{secrets.token_hex(6)}"
    pair2_rel = pair_dir + f"/second_{secrets.token_hex(6)}"

    write_file(ROOT + "/" + hidden_rel, secrets.token_bytes(137))
    write_file(ROOT + "/" + regular_rel, secrets.token_bytes(311))
    os.symlink(ROOT + "/" + regular_rel, ROOT + "/" + valid_rel)
    os.symlink(os.path.basename(self_rel), ROOT + "/" + self_rel)
    os.symlink(ROOT + "/" + pair2_rel, ROOT + "/" + pair1_rel)
    os.symlink(ROOT + "/" + pair1_rel, ROOT + "/" + pair2_rel)

    loop_rels = [
        "appB/loop1",
        "appB/loop2",
        "appC/loop_self",
        self_rel,
        pair1_rel,
        pair2_rel,
    ]
    initial = snapshot_tree()
    expected = dict(initial)
    for rel in loop_rels:
        entry = expected.pop(rel)
        expected[rel + ".broken"] = entry

    for path in (LOG, TMP_ARCHIVE, ARCHIVE):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    fd = start_inotify()
    try:
        proc = subprocess.Popen([exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            stdout, stderr = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("Execution timed out; traversal may have followed a symlink loop.")
        events = read_inotify(fd)
    finally:
        os.close(fd)

    assert proc.returncode == 0, f"Execution failed:\n{stderr}"

    STATE.update({
        "loop_rels": loop_rels,
        "valid_rel": valid_rel,
        "valid_target": ROOT + "/" + regular_rel,
        "expected": expected,
        "events": events,
    })


def test_broken_links_renamed():
    expected_broken = [
        ROOT + "/appB/loop1.broken",
        ROOT + "/appB/loop2.broken",
        ROOT + "/appC/loop_self.broken",
    ]
    expected_missing = [
        ROOT + "/appB/loop1",
        ROOT + "/appB/loop2",
        ROOT + "/appC/loop_self",
    ]

    for path in expected_broken:
        assert os.path.islink(path), f"Expected renamed symlink {path} is missing."
    for path in expected_missing:
        assert not os.path.exists(path) and not os.path.islink(path), (
            f"Original looping symlink {path} should have been renamed."
        )

    for rel in STATE["loop_rels"]:
        assert os.path.islink(ROOT + "/" + rel + ".broken")
        assert not os.path.lexists(ROOT + "/" + rel)

    assert snapshot_tree() == STATE["expected"], (
        "The configuration tree was not recursively sanitized exactly as required, "
        "or a valid file, directory, or symlink was modified."
    )


def test_valid_symlinks_untouched():
    valid_link = ROOT + "/appA/config_link.ini"
    assert os.path.islink(valid_link), f"Valid symlink {valid_link} was incorrectly modified or deleted."
    assert os.readlink(valid_link) == ROOT + "/appA/config.ini", f"Valid symlink {valid_link} target changed."

    generated = ROOT + "/" + STATE["valid_rel"]
    assert os.path.islink(generated)
    assert os.readlink(generated) == STATE["valid_target"]


def test_broken_links_log():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    fixed_expected = {
        ROOT + "/appB/loop1",
        ROOT + "/appB/loop2",
        ROOT + "/appC/loop_self",
    }
    assert fixed_expected.issubset(set(lines))

    expected_lines = {ROOT + "/" + rel for rel in STATE["loop_rels"]}
    assert set(lines) == expected_lines, f"Log file contents incorrect. Expected {expected_lines}, got {set(lines)}"
    assert len(lines) == len(expected_lines), "Log file contains duplicate or extra entries."


def test_atomic_archive_creation():
    assert os.path.isfile(ARCHIVE), f"Final archive {ARCHIVE} is missing."
    assert not os.path.exists(TMP_ARCHIVE), f"Temporary archive {TMP_ARCHIVE} was not cleaned up / renamed."
    assert tarfile.is_tarfile(ARCHIVE), f"File {ARCHIVE} is not a valid tar archive."

    events = STATE["events"]
    tmp_name = os.path.basename(TMP_ARCHIVE)
    final_name = os.path.basename(ARCHIVE)
    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100

    assert not any((mask & IN_CREATE) and name == final_name for mask, cookie, name in events), (
        "The final archive was created directly instead of appearing through an atomic rename."
    )
    moves_from = [(i, cookie) for i, (mask, cookie, name) in enumerate(events)
                  if (mask & IN_MOVED_FROM) and name == tmp_name]
    moves_to = [(i, cookie) for i, (mask, cookie, name) in enumerate(events)
                if (mask & IN_MOVED_TO) and name == final_name]
    matching = [(a, b, ca) for a, ca in moves_from for b, cb in moves_to if ca and ca == cb and a < b]
    assert matching, "No atomic rename from config_backup.tar.gz.tmp to config_backup.tar.gz was observed."
    move_from_i, move_to_i, _ = matching[-1]
    assert any(i < move_from_i and name == tmp_name and (mask & IN_CLOSE_WRITE)
               for i, (mask, cookie, name) in enumerate(events)), (
        "The temporary archive was not completely closed before it was renamed."
    )
    assert not any(i > move_to_i and name == final_name and (mask & (IN_MODIFY | IN_CLOSE_WRITE))
                   for i, (mask, cookie, name) in enumerate(events)), (
        "The archive continued to be written after becoming visible at the final path."
    )

    archived = {}
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        names = tar.getnames()
        assert any("appB/loop1.broken" in name for name in names), "Archive does not contain the renamed broken links."
        assert any("appA/config.ini" in name for name in names), "Archive does not contain the normal config files."

        for member in tar.getmembers():
            rel = canonical_member(member.name)
            if not rel:
                continue
            assert rel not in archived, f"Archive contains duplicate member {rel}"
            if member.isdir():
                archived[rel] = ("dir", None)
            elif member.issym():
                archived[rel] = ("symlink", member.linkname)
            elif member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                archived[rel] = ("file", extracted.read())
            else:
                archived[rel] = ("other", member.type)

    assert archived == STATE["expected"], (
        "The gzip tar archive does not contain exactly the entire sanitized configuration tree "
        "with the correct file contents, directories, and symlink targets."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
