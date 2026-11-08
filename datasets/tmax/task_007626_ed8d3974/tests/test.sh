#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile
import pytest

CURATED = "/home/user/curated_repo"
ARCHIVE = "/home/user/artifacts.tar"

# Trusted semantic manifest of the archive created by setup. This also prevents
# the submission from changing the archive used to derive expected results.
EXPECTED_REGULAR = {
    "readme.txt": b"Legacy System v1.0\nFeatures: \xfcber fast execution.\n",
    "core system app.bin": b"\x7fELF...core",
    "diagnostic tool.bin": b"\x7fELF...diag",
}
EXPECTED_SYMLINKS = {
    "system_passwords": "/etc/passwd",
    "info.txt": "readme.txt",
}


def archive_manifest():
    regular = {}
    symlinks = {}
    other = []
    with tarfile.open(ARCHIVE, "r:*") as tf:
        for member in tf.getmembers():
            name = member.name.rstrip("/")
            if member.isfile():
                stream = tf.extractfile(member)
                assert stream is not None
                regular[name] = stream.read()
            elif member.issym():
                symlinks[name] = member.linkname
            elif member.isdir():
                pass
            else:
                other.append((name, member.type))
    return regular, symlinks, other


def renamed_bin(name):
    directory, basename = os.path.split(name)
    basename = basename[:-4].replace(" ", "_") + ".elf"
    return os.path.join(directory, basename) if directory else basename


def contained(path):
    return os.path.commonpath((os.path.realpath(path), os.path.realpath(CURATED))) == os.path.realpath(CURATED)


def walk_without_following_links(root):
    pending = [root]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                yield entry.path
                if entry.is_dir(follow_symlinks=False):
                    pending.append(entry.path)


def test_archive_is_original_input():
    regular, symlinks, other = archive_manifest()
    assert regular == EXPECTED_REGULAR
    assert symlinks == EXPECTED_SYMLINKS
    assert other == []


def test_symlink_sanitization():
    curated_repo = "/home/user/curated_repo"
    bad_symlink = os.path.join(curated_repo, "system_passwords")
    good_symlink = os.path.join(curated_repo, "info.txt")

    assert not os.path.exists(bad_symlink) and not os.path.islink(bad_symlink), \
        f"Malicious symlink {bad_symlink} should have been deleted."

    assert os.path.islink(good_symlink), \
        f"Valid symlink {good_symlink} should still exist."


def test_all_paths_are_sanitized_and_safe_links_are_preserved():
    assert os.path.isdir(CURATED) and not os.path.islink(CURATED)

    for path in walk_without_following_links(CURATED):
        assert contained(path), f"Extracted path {path} resolves outside {CURATED}"

    good = os.path.join(CURATED, "info.txt")
    assert os.path.islink(good)
    assert os.readlink(good) == EXPECTED_SYMLINKS["info.txt"]
    assert os.path.realpath(good) == os.path.join(CURATED, "readme.txt")

    bad = os.path.join(CURATED, "system_passwords")
    assert not os.path.lexists(bad), f"Unsafe archived symlink {bad} was not removed"


def test_utf8_conversion():
    readme_path = "/home/user/curated_repo/readme.txt"
    assert os.path.exists(readme_path), f"{readme_path} is missing."

    try:
        with open(readme_path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        pytest.fail(f"{readme_path} is not valid UTF-8.")

    assert "über fast execution" in content, \
        f"Expected converted text not found in {readme_path}. Found: {content}"


def test_all_text_contents_match_archive_conversion():
    regular, _, _ = archive_manifest()
    expected_txt = {name: data.decode("iso-8859-1").encode("utf-8")
                    for name, data in regular.items() if name.endswith(".txt")}
    for name, expected in expected_txt.items():
        path = os.path.join(CURATED, name)
        assert os.path.isfile(path) and not os.path.islink(path), f"Missing converted text file {path}"
        with open(path, "rb") as f:
            assert f.read() == expected, f"Converted contents of {path} do not match the archived file"


def test_file_renaming():
    curated_repo = "/home/user/curated_repo"
    expected_files = ["core_system_app.elf", "diagnostic_tool.elf"]
    unexpected_files = ["core system app.bin", "diagnostic tool.bin"]

    for f in expected_files:
        path = os.path.join(curated_repo, f)
        assert os.path.exists(path), f"Expected renamed file {path} is missing."

    for f in unexpected_files:
        path = os.path.join(curated_repo, f)
        assert not os.path.exists(path), f"Old file {path} should not exist."


def test_all_renamed_binaries_match_archived_bytes():
    regular, _, _ = archive_manifest()
    expected = {renamed_bin(name): data for name, data in regular.items() if name.endswith(".bin")}

    found_source_elf = set()
    for path in walk_without_following_links(CURATED):
        relative = os.path.relpath(path, CURATED)
        if relative == "release" or relative.startswith("release" + os.sep):
            continue
        if path.endswith(".bin"):
            pytest.fail(f"Unrenamed .bin file remains: {path}")
        if path.endswith(".elf") and os.path.isfile(path):
            found_source_elf.add(relative)

    assert found_source_elf == set(expected), \
        f"Renamed .elf set differs from archive: {found_source_elf}"
    for relative, expected_bytes in expected.items():
        path = os.path.join(CURATED, relative)
        assert not os.path.islink(path)
        with open(path, "rb") as f:
            assert f.read() == expected_bytes, f"{path} does not contain the archived binary bytes"


def test_hard_links():
    curated_repo = "/home/user/curated_repo"
    release_dir = os.path.join(curated_repo, "release")

    assert os.path.isdir(release_dir), f"{release_dir} directory is missing."

    files_to_check = ["core_system_app.elf", "diagnostic_tool.elf"]
    for f in files_to_check:
        orig_path = os.path.join(curated_repo, f)
        link_path = os.path.join(release_dir, f)

        assert os.path.exists(link_path), f"Hard link {link_path} is missing."

        orig_stat = os.stat(orig_path)
        link_stat = os.stat(link_path)

        assert orig_stat.st_ino == link_stat.st_ino, \
            f"{link_path} is not a hard link to {orig_path} (inodes differ)."


def test_release_contains_hard_links_for_every_archived_binary():
    regular, _, _ = archive_manifest()
    expected_names = sorted(os.path.basename(renamed_bin(name))
                            for name in regular if name.endswith(".bin"))
    release = os.path.join(CURATED, "release")
    assert os.path.isdir(release) and not os.path.islink(release)
    assert sorted(os.listdir(release)) == expected_names

    for archived_name in regular:
        if not archived_name.endswith(".bin"):
            continue
        source = os.path.join(CURATED, renamed_bin(archived_name))
        link = os.path.join(release, os.path.basename(renamed_bin(archived_name)))
        source_stat = os.stat(source)
        link_stat = os.stat(link)
        assert stat.S_ISREG(link_stat.st_mode) and not os.path.islink(link)
        assert (source_stat.st_dev, source_stat.st_ino) == (link_stat.st_dev, link_stat.st_ino)
        with open(link, "rb") as f:
            assert f.read() == regular[archived_name]


def test_latest_symlink():
    symlink_path = "/home/user/curated_repo/latest"
    expected_target_name = "release"
    expected_target_abs = "/home/user/curated_repo/release"

    assert os.path.islink(symlink_path), f"{symlink_path} should be a symbolic link."

    target = os.readlink(symlink_path)
    assert target in (expected_target_name, expected_target_abs), \
        f"Symlink {symlink_path} points to {target}, expected {expected_target_name} or {expected_target_abs}."


def test_audit_log():
    log_path = "/home/user/audit.log"
    assert os.path.exists(log_path), f"Audit log {log_path} is missing."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["core_system_app.elf", "diagnostic_tool.elf"]
    assert lines == expected_lines, \
        f"Audit log contents incorrect. Expected {expected_lines}, got {lines}."


def test_audit_log_is_exact_sorted_release_listing():
    release = os.path.join(CURATED, "release")
    expected = sorted(os.path.basename(name) for name in os.listdir(release))
    with open("/home/user/audit.log", "r", encoding="utf-8") as f:
        raw = f.read()
    assert raw == "".join(name + "\n" for name in expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
