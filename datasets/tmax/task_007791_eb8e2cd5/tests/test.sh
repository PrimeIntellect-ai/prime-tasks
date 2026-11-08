#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

BACKUP_DEST = "/home/user/backup_dest"
BACKUP_LOG = "/home/user/backup_log.txt"

def test_backup_dest_exists():
    assert os.path.isdir(BACKUP_DEST), f"Destination directory {BACKUP_DEST} was not created or is not a directory."

def test_old_files_not_copied():
    old1 = os.path.join(BACKUP_DEST, "folderA", "old1.txt")
    old2 = os.path.join(BACKUP_DEST, "folderB", "old2.txt")
    old1_hlink = os.path.join(BACKUP_DEST, "folderB", "old1_hlink.txt")
    assert not os.path.exists(old1), "old1.txt should not have been copied (older than last_backup.ts)."
    assert not os.path.exists(old2), "old2.txt should not have been copied (older than last_backup.ts)."
    assert not os.path.exists(old1_hlink), "old1_hlink.txt should not have been copied (older than last_backup.ts)."

def test_new_files_and_hardlinks_copied():
    new1 = os.path.join(BACKUP_DEST, "folderA", "new1.txt")
    new2 = os.path.join(BACKUP_DEST, "folderA", "new2.txt")
    new1_hlink = os.path.join(BACKUP_DEST, "folderB", "new1_hlink.txt")
    new2_hlink = os.path.join(BACKUP_DEST, "folderA", "new2_hlink.txt")
    assert os.path.isfile(new1) and not os.path.islink(new1), "new1.txt was not copied correctly."
    assert os.path.isfile(new2) and not os.path.islink(new2), "new2.txt was not copied correctly."
    assert os.path.isfile(new1_hlink) and not os.path.islink(new1_hlink), "new1_hlink.txt was not copied correctly."
    assert os.path.isfile(new2_hlink) and not os.path.islink(new2_hlink), "new2_hlink.txt was not copied correctly."
    assert os.stat(new1).st_ino == os.stat(new1_hlink).st_ino, "new1.txt and new1_hlink.txt do not share the same inode in destination."
    assert os.stat(new2).st_ino == os.stat(new2_hlink).st_ino, "new2.txt and new2_hlink.txt do not share the same inode in destination."

def test_regular_file_contents():
    for rel in ("folderA/new1.txt", "folderA/new2.txt", "folderB/new1_hlink.txt", "folderA/new2_hlink.txt"):
        with open(os.path.join("/home/user/data_source", rel), "rb") as src:
            expected = src.read()
        with open(os.path.join(BACKUP_DEST, rel), "rb") as dst:
            assert dst.read() == expected, f"Contents were not preserved for {rel}."

def test_symlinks_copied_correctly():
    sym_old = os.path.join(BACKUP_DEST, "folderB", "sym_to_old.txt")
    sym_new = os.path.join(BACKUP_DEST, "folderB", "sym_to_new.txt")
    assert os.path.islink(sym_old), "sym_to_old.txt was not copied as a symlink."
    assert os.path.islink(sym_new), "sym_to_new.txt was not copied as a symlink."
    assert os.readlink(sym_old) == "../folderA/old1.txt", "sym_to_old.txt target was not preserved."
    assert os.readlink(sym_new) == "../folderA/new1.txt", "sym_to_new.txt target was not preserved."

def test_backup_log_exists_and_format():
    assert os.path.isfile(BACKUP_LOG), f"Log file {BACKUP_LOG} is missing."
    with open(BACKUP_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_items = {
        "folderA/new1.txt", "folderA/new2.txt", "folderA/new2_hlink.txt",
        "folderB/new1_hlink.txt", "folderB/sym_to_new.txt", "folderB/sym_to_old.txt"
    }
    parsed_items = []
    log_dict = {}
    for line in lines:
        parts = line.split(" ", 1)
        assert len(parts) == 2, f"Log line format invalid: {line}"
        item_type, path = parts
        assert item_type in ("[FILE]", "[HLINK]", "[SLINK]"), f"Invalid type marker {item_type} in log."
        parsed_items.append(path)
        log_dict[path] = item_type
    assert len(parsed_items) == len(set(parsed_items)), "The log contains duplicate paths."
    assert set(parsed_items) == expected_items, f"Log items do not match expected backed up files. Expected: {expected_items}, Got: {set(parsed_items)}"
    assert parsed_items == sorted(parsed_items), "Log file is not sorted alphabetically by relative path."
    assert log_dict["folderB/sym_to_new.txt"] == "[SLINK]", "sym_to_new.txt should be marked as [SLINK]"
    assert log_dict["folderB/sym_to_old.txt"] == "[SLINK]", "sym_to_old.txt should be marked as [SLINK]"
    for group in (["folderA/new1.txt", "folderB/new1_hlink.txt"], ["folderA/new2.txt", "folderA/new2_hlink.txt"]):
        types = [log_dict[path] for path in group]
        assert types.count("[FILE]") == 1, f"Expected exactly one [FILE] for shared inode group {group}."
        assert types.count("[HLINK]") == len(group) - 1, f"Expected the remaining entries to be [HLINK] for {group}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_backup.py
import os
import shutil
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path

SOURCE = Path("/home/user/data_source")
DEST = Path("/home/user/backup_dest")
LOG = Path("/home/user/backup_log.txt")
STAMP = Path("/home/user/last_backup.ts")
EXCLUDED = {SOURCE, DEST, LOG, STAMP, Path("/tmp/test_final_state.py"), Path("/tmp/test_dynamic_backup.py")}

def under(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False

def discover_scripts():
    cutoff = STAMP.stat().st_mtime
    candidates = []
    roots = [Path("/home/user"), Path("/root"), Path("/workspace"), Path("/tmp")]
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        for base, dirs, files in os.walk(root):
            basep = Path(base)
            dirs[:] = [d for d in dirs if not under(basep / d, SOURCE) and not under(basep / d, DEST) and d not in {".cache", ".local", "__pycache__"}]
            for name in files:
                path = basep / name
                if path in EXCLUDED or under(path, SOURCE) or under(path, DEST):
                    continue
                try:
                    st = path.stat()
                    if not stat.S_ISREG(st.st_mode) or st.st_mtime <= cutoff:
                        continue
                    first = path.read_bytes()[:128]
                except (OSError, PermissionError):
                    continue
                suffix = path.suffix.lower()
                script_like = suffix in {".py", ".sh", ".bash"} or first.startswith(b"#!") or bool(st.st_mode & 0o111)
                if script_like and path not in seen:
                    seen.add(path)
                    candidates.append(path)
    return sorted(candidates, key=lambda p: (0 if "backup" in p.name.lower() else 1, str(p)))

def make_fixture(token):
    shutil.rmtree(SOURCE, ignore_errors=True)
    shutil.rmtree(DEST, ignore_errors=True)
    try:
        LOG.unlink()
    except FileNotFoundError:
        pass

    a = f"alpha_{token}"
    b = f"nested_{token}/beta_{token}"
    c = f"links_{token}"
    (SOURCE / a).mkdir(parents=True)
    (SOURCE / b).mkdir(parents=True)
    (SOURCE / c).mkdir(parents=True)
    (SOURCE / f"empty_{token}").mkdir()

    old_rel = f"{a}/old_payload.txt"
    old2_rel = f"{b}/old_other.bin"
    single_rel = f"{b}/fresh_payload.bin"
    hard1_rel = f"{a}/shared_origin.dat"
    hard2_rel = f"{b}/shared_second.dat"
    hard3_rel = f"{c}/shared_third.dat"
    sym1_rel = f"{c}/old_pointer"
    sym2_rel = f"{a}/dangling_pointer"

    payloads = {
        old_rel: ("old-" + token).encode(),
        old2_rel: os.urandom(31),
        single_rel: b"dynamic-content\x00" + os.urandom(73),
        hard1_rel: b"hard-linked-content-" + os.urandom(47),
    }
    for rel, data in payloads.items():
        (SOURCE / rel).write_bytes(data)
    os.link(SOURCE / hard1_rel, SOURCE / hard2_rel)
    os.link(SOURCE / hard1_rel, SOURCE / hard3_rel)

    now = time.time()
    old_time = now - 120
    ref_time = now - 60
    new_time = now - 5
    os.utime(SOURCE / old_rel, (old_time, old_time))
    os.utime(SOURCE / old2_rel, (old_time, old_time))
    os.utime(SOURCE / single_rel, (new_time, new_time))
    os.utime(SOURCE / hard1_rel, (new_time, new_time))
    STAMP.touch()
    os.utime(STAMP, (ref_time, ref_time))

    target1 = f"../{a}/old_payload.txt"
    target2 = f"missing_{token}/target"
    os.symlink(target1, SOURCE / sym1_rel)
    os.symlink(target2, SOURCE / sym2_rel)

    return {
        "old": {old_rel, old2_rel},
        "regular": {single_rel, hard1_rel, hard2_rel, hard3_rel},
        "hard": {hard1_rel, hard2_rel, hard3_rel},
        "symlinks": {sym1_rel: target1, sym2_rel: target2},
        "contents": {
            single_rel: payloads[single_rel], hard1_rel: payloads[hard1_rel],
            hard2_rel: payloads[hard1_rel], hard3_rel: payloads[hard1_rel]
        },
    }

def command_for(path):
    if path.suffix.lower() == ".py":
        return [sys.executable, str(path)]
    if path.suffix.lower() in {".sh", ".bash"}:
        return ["bash", str(path)]
    try:
        first = path.read_text(errors="ignore").splitlines()[0]
    except Exception:
        first = ""
    if "python" in first:
        return [sys.executable, str(path)]
    if "sh" in first:
        return ["bash", str(path)]
    return [str(path)]

def verify(expected):
    assert DEST.is_dir(), "backup destination was not created"
    expected_items = expected["regular"] | set(expected["symlinks"])

    found = set()
    for base, dirs, files in os.walk(DEST, followlinks=False):
        for name in files:
            found.add((Path(base) / name).relative_to(DEST).as_posix())
    assert found == expected_items, f"destination items differ: expected {expected_items}, got {found}"
    for rel in expected["old"]:
        assert not os.path.lexists(DEST / rel), f"old file was copied: {rel}"
    for rel, content in expected["contents"].items():
        path = DEST / rel
        assert path.is_file() and not path.is_symlink(), f"regular file missing or wrong type: {rel}"
        assert path.read_bytes() == content, f"regular file content differs: {rel}"
        assert os.stat(path).st_ino != os.stat(SOURCE / rel).st_ino, f"source file was linked instead of copied: {rel}"
    hard_inodes = {os.stat(DEST / rel).st_ino for rel in expected["hard"]}
    assert len(hard_inodes) == 1, "hard-link group was not preserved"
    for rel, target in expected["symlinks"].items():
        path = DEST / rel
        assert path.is_symlink(), f"symlink was not preserved: {rel}"
        assert os.readlink(path) == target, f"symlink target differs: {rel}"

    expected_dirs = set()
    for rel in expected_items:
        parent = Path(rel).parent
        while str(parent) != ".":
            expected_dirs.add(parent.as_posix())
            parent = parent.parent
    actual_dirs = set()
    for base, dirs, files in os.walk(DEST, followlinks=False):
        for name in dirs:
            path = Path(base) / name
            if not path.is_symlink():
                actual_dirs.add(path.relative_to(DEST).as_posix())
    assert actual_dirs == expected_dirs, f"unexpected empty/extraneous directories: {actual_dirs - expected_dirs}"

    assert LOG.is_file() and not LOG.is_symlink(), "backup log was not generated as a regular file"
    raw_lines = LOG.read_text().splitlines()
    assert raw_lines and all(line.strip() == line and line for line in raw_lines), "log contains blank or malformed whitespace-only lines"
    assert raw_lines == sorted(raw_lines, key=lambda line: line.split(" ", 1)[1] if " " in line else line), "log is not sorted by relative path"
    parsed = {}
    for line in raw_lines:
        parts = line.split(" ", 1)
        assert len(parts) == 2 and parts[0] in {"[FILE]", "[HLINK]", "[SLINK]"}, f"invalid log line: {line}"
        assert parts[1] not in parsed, f"duplicate log path: {parts[1]}"
        parsed[parts[1]] = parts[0]
    assert set(parsed) == expected_items, f"log items differ: expected {expected_items}, got {set(parsed)}"
    for rel in expected["symlinks"]:
        assert parsed[rel] == "[SLINK]", f"wrong log type for symlink {rel}"
    assert parsed[next(iter(expected["regular"] - expected["hard"]))] == "[FILE]"
    hard_types = [parsed[rel] for rel in expected["hard"]]
    assert hard_types.count("[FILE]") == 1 and hard_types.count("[HLINK]") == len(hard_types) - 1, "hard-link log classification is wrong"

def main():
    candidates = discover_scripts()
    assert candidates, "no reusable backup script was found"
    failures = []
    for index, script in enumerate(candidates):
        token = uuid.uuid4().hex[:10]
        expected = make_fixture(token)
        try:
            result = subprocess.run(command_for(script), cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            if result.returncode != 0:
                raise AssertionError(f"script exited with status {result.returncode}")
            verify(expected)
            print(f"Validated reusable backup script: {script}")
            return
        except Exception as exc:
            failures.append(f"{script}: {exc}")
    raise AssertionError("No discovered script performed a correct backup on a fresh fixture. " + " | ".join(failures))

if __name__ == "__main__":
    main()
DYNAMIC_EOF

ok=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_dynamic_backup.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
