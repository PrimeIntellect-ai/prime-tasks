#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_curator_executable_exists():
    curator_path = "/home/user/curator"
    assert os.path.isfile(curator_path), f"Executable {curator_path} does not exist."
    st = os.stat(curator_path)
    assert st.st_mode & stat.S_IXUSR, f"Executable {curator_path} is not executable."
    with open(curator_path, "rb") as f:
        ident = f.read(5)
    assert ident[:4] == b"\x7fELF" and ident[4] == 2, f"{curator_path} is not a compiled 64-bit ELF executable."


def test_curator_source_exists():
    source_path = "/home/user/curator.c"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."


def test_repo_files_exist():
    expected_files = [
        "a_first.bin",
        "b_second.bin",
        "c_third.bin",
        "f_fourth.bin"
    ]
    for filename in expected_files:
        filepath = os.path.join("/home/user/artifacts_repo", filename)
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing in artifacts_repo."


def test_ignored_files_do_not_exist():
    ignored_files = [
        "d_active.tmp",
        "e_text.txt"
    ]
    for filename in ignored_files:
        filepath = os.path.join("/home/user/artifacts_repo", filename)
        assert not os.path.exists(filepath), f"Ignored file {filepath} should NOT be in artifacts_repo."


def test_hard_links():
    repo_dir = "/home/user/artifacts_repo"

    a_first = os.path.join(repo_dir, "a_first.bin")
    c_third = os.path.join(repo_dir, "c_third.bin")
    b_second = os.path.join(repo_dir, "b_second.bin")
    f_fourth = os.path.join(repo_dir, "f_fourth.bin")

    assert os.path.exists(a_first) and os.path.exists(c_third), "Missing files for hardlink check (a_first, c_third)"
    assert os.path.exists(b_second) and os.path.exists(f_fourth), "Missing files for hardlink check (b_second, f_fourth)"

    stat_a = os.stat(a_first)
    stat_c = os.stat(c_third)

    assert stat_a.st_nlink >= 2, f"{a_first} does not have multiple hard links."
    assert stat_a.st_ino == stat_c.st_ino, f"{a_first} and {c_third} are not hard linked."

    stat_b = os.stat(b_second)
    stat_f = os.stat(f_fourth)

    assert stat_b.st_nlink >= 2, f"{b_second} does not have multiple hard links."
    assert stat_b.st_ino == stat_f.st_ino, f"{b_second} and {f_fourth} are not hard linked."


def test_latest_symlink():
    symlink_path = "/home/user/artifacts_repo/latest.elf"
    assert os.path.islink(symlink_path), f"{symlink_path} does not exist or is not a symlink."

    target = os.readlink(symlink_path)
    if not os.path.isabs(target):
        target = os.path.join("/home/user/artifacts_repo", target)

    target_norm = os.path.normpath(target)
    expected_target = "/home/user/artifacts_repo/f_fourth.bin"

    assert target_norm == expected_target, f"latest.elf symlink points to {target_norm}, expected {expected_target}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import os
import secrets
import shutil
import struct
import subprocess

INPUT = "/home/user/artifacts_in"
REPO = "/home/user/artifacts_repo"
SOURCE = "/home/user/curator.c"
COMPILED_SOURCE = "/tmp/curator_from_source"


def elf64(entry, payload, elf_class=2, magic=b"\x7fELF"):
    data = bytearray(64)
    data[0:4] = magic
    data[4] = elf_class
    data[5] = 1
    data[6] = 1
    struct.pack_into("<Q", data, 24, entry)
    return bytes(data) + payload


def write_file(name, data):
    with open(os.path.join(INPUT, name), "wb") as f:
        f.write(data)


def exercise(executable, preexisting_latest_kind):
    shutil.rmtree(INPUT, ignore_errors=True)
    shutil.rmtree(REPO, ignore_errors=True)
    os.makedirs(INPUT)
    os.makedirs(REPO)

    prefix = secrets.token_hex(6) + "_"
    high = secrets.randbits(48) << 8
    entry1 = high | 0x11
    entry2 = high | 0x22
    entry3 = high | 0x33
    entry4 = high | 0x44

    names = {
        "a": prefix + "a_alpha.bin",
        "b": prefix + "b_beta.bin",
        "c": prefix + "c_clone.bin",
        "tmp": prefix + "d_busy.tmp",
        "bad": prefix + "e_bad.bin",
        "suffix": prefix + "f_tmp_named.tmp.bin",
        "g": prefix + "g_clone2.bin",
        "class32": prefix + "h_32.bin",
    }

    contents = {
        "a": elf64(entry1, b"first representative"),
        "b": elf64(entry2, b"second representative"),
        "c": elf64(entry1, b"different duplicate payload"),
        "tmp": elf64(entry3, b"must be ignored"),
        "bad": b"not an elf at all",
        "suffix": elf64(entry4, b"name does not end in dot tmp"),
        "g": elf64(entry2, b"another duplicate payload"),
        "class32": elf64(entry3, b"wrong class", elf_class=1),
    }
    for key, name in names.items():
        write_file(name, contents[key])

    os.mkdir(os.path.join(INPUT, prefix + "i_directory.bin"))
    latest = os.path.join(REPO, "latest.elf")
    if preexisting_latest_kind == "file":
        with open(latest, "wb") as f:
            f.write(b"old latest")
    else:
        os.symlink("missing-old-target", latest)

    subprocess.run([executable], check=True, timeout=15)

    expected = [names[k] for k in ("a", "b", "c", "suffix", "g")]
    for name in expected:
        path = os.path.join(REPO, name)
        assert os.path.isfile(path), f"dynamic run did not publish {name}"

    for key in ("tmp", "bad", "class32"):
        assert not os.path.lexists(os.path.join(REPO, names[key])), f"dynamic run incorrectly published {names[key]}"

    a = os.path.join(REPO, names["a"])
    b = os.path.join(REPO, names["b"])
    c = os.path.join(REPO, names["c"])
    suffix = os.path.join(REPO, names["suffix"])
    g = os.path.join(REPO, names["g"])

    assert os.stat(a).st_ino == os.stat(c).st_ino, "equal randomized entry points were not hard linked"
    assert os.stat(b).st_ino == os.stat(g).st_ino, "second equal randomized entry-point pair was not hard linked"
    assert os.stat(a).st_ino != os.stat(b).st_ino, "different entry points were incorrectly deduplicated"
    assert os.stat(suffix).st_ino not in (os.stat(a).st_ino, os.stat(b).st_ino), "unique entry point was incorrectly deduplicated"
    assert os.stat(a).st_nlink >= 2 and os.stat(b).st_nlink >= 2

    with open(a, "rb") as f:
        assert f.read() == contents["a"], "first occurrence was not copied byte-for-byte"
    with open(b, "rb") as f:
        assert f.read() == contents["b"], "second representative was not copied byte-for-byte"
    with open(suffix, "rb") as f:
        assert f.read() == contents["suffix"], "valid file containing .tmp in its name was not copied correctly"

    assert os.path.islink(latest), "latest.elf was not replaced with a symlink"
    target = os.readlink(latest)
    if not os.path.isabs(target):
        target = os.path.join(REPO, target)
    assert os.path.normpath(target) == os.path.join(REPO, names["g"]), "latest.elf does not point to the last alphabetically processed valid ELF"


subprocess.run(["gcc", SOURCE, "-o", COMPILED_SOURCE], check=True, timeout=30)
exercise("/home/user/curator", "file")
exercise(COMPILED_SOURCE, "symlink")
DYNAMIC_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_dynamic.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
