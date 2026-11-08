#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile

ARTIFACTS_DIR = "/home/user/artifacts"
BACKUP_ARCHIVE = "/home/user/artifacts_backup.tar.gz"


def test_loop_symlink_removed():
    loop_link = os.path.join(ARTIFACTS_DIR, "v3", "loop_link")
    assert not os.path.exists(loop_link) and not os.path.islink(loop_link), (
        f"The circular symlink {loop_link} should have been deleted."
    )


def test_valid_symlink_intact():
    latest_link = os.path.join(ARTIFACTS_DIR, "latest")
    assert os.path.islink(latest_link), f"The valid symlink {latest_link} should still exist."
    target = os.readlink(latest_link)
    expected_target = os.path.join(ARTIFACTS_DIR, "v3")
    assert target == expected_target or target == "v3", (
        f"The symlink {latest_link} should point to {expected_target} or 'v3'."
    )


def test_deduplication_hardlinks_and_contents():
    v1_bin = os.path.join(ARTIFACTS_DIR, "v1", "app.bin")
    v2_bin = os.path.join(ARTIFACTS_DIR, "v2", "app.bin")
    v3_bin = os.path.join(ARTIFACTS_DIR, "v3", "app.bin")

    assert os.path.isfile(v1_bin), f"File {v1_bin} is missing."
    assert os.path.isfile(v2_bin), f"File {v2_bin} is missing."
    assert os.path.isfile(v3_bin), f"File {v3_bin} is missing."
    assert stat.S_ISREG(os.lstat(v1_bin).st_mode), f"{v1_bin} must be a regular file."
    assert stat.S_ISREG(os.lstat(v2_bin).st_mode), f"{v2_bin} must be a regular file."
    assert stat.S_ISREG(os.lstat(v3_bin).st_mode), f"{v3_bin} must be a regular file."

    with open(v1_bin, "rb") as f:
        data1 = f.read()
    with open(v2_bin, "rb") as f:
        data2 = f.read()
    with open(v3_bin, "rb") as f:
        data3 = f.read()

    # These are invariant properties of the files produced by setup. They prevent
    # replacing the binaries with empty or otherwise truncated placeholder files.
    assert len(data1) == 1024, f"{v1_bin} no longer has its original size."
    assert len(data2) == 1024, f"{v2_bin} no longer has its original size."
    assert len(data3) == 1029, f"{v3_bin} no longer has its original size."
    assert data3.endswith(b"diff\n"), f"{v3_bin} lost its original trailing marker."
    assert data1 == data2, f"{v1_bin} and {v2_bin} no longer contain identical data."
    assert data1 != data3, f"{v3_bin} must retain content different from {v1_bin}."

    stat1 = os.stat(v1_bin)
    stat2 = os.stat(v2_bin)
    stat3 = os.stat(v3_bin)

    assert stat1.st_ino == stat2.st_ino, (
        f"{v1_bin} and {v2_bin} should be hardlinked (same inode) because they are identical."
    )
    assert stat1.st_dev == stat2.st_dev, (
        f"{v1_bin} and {v2_bin} must be hardlinks on the same filesystem."
    )
    assert stat1.st_ino != stat3.st_ino or stat1.st_dev != stat3.st_dev, (
        f"{v3_bin} should NOT be hardlinked to {v1_bin} because they have different contents."
    )


def test_backup_archive_exists_valid_and_faithful():
    assert os.path.isfile(BACKUP_ARCHIVE), f"Backup archive {BACKUP_ARCHIVE} does not exist."
    assert tarfile.is_tarfile(BACKUP_ARCHIVE), f"{BACKUP_ARCHIVE} is not a valid tar archive."

    current_paths = {
        "v1/app.bin": os.path.join(ARTIFACTS_DIR, "v1", "app.bin"),
        "v2/app.bin": os.path.join(ARTIFACTS_DIR, "v2", "app.bin"),
        "v3/app.bin": os.path.join(ARTIFACTS_DIR, "v3", "app.bin"),
    }

    with tarfile.open(BACKUP_ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()

        def matching_members(ending):
            ending = ending.strip("/")
            result = []
            for member in members:
                name = member.name.strip("/")
                if name == ending or name.endswith("/" + ending):
                    result.append(member)
            return result

        selected = {}
        for ending in current_paths:
            matches = matching_members(ending)
            assert matches, f"Archive is missing {ending}."
            assert len(matches) == 1, f"Archive contains ambiguous duplicate entries for {ending}."
            selected[ending] = matches[0]

        latest_matches = matching_members("latest")
        assert latest_matches, "Archive is missing 'latest' symlink."
        assert len(latest_matches) == 1, "Archive contains ambiguous duplicate entries for latest."
        latest = latest_matches[0]
        assert latest.issym(), "The archived latest entry must remain a symlink."
        expected_target = os.path.join(ARTIFACTS_DIR, "v3")
        assert latest.linkname in (expected_target, "v3"), (
            "The archived latest symlink has the wrong target."
        )

        assert not matching_members("v3/loop_link"), "Archive should NOT contain the loop_link."

        # A backup containing only the required names is insufficient: each binary
        # member must contain exactly the bytes present in the cleaned repository.
        for ending, filesystem_path in current_paths.items():
            member = selected[ending]
            assert member.isfile() or member.islnk(), (
                f"Archived {ending} must be a regular file or a tar hard-link entry."
            )
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived contents for {ending}."
            archived_data = extracted.read()
            with open(filesystem_path, "rb") as f:
                filesystem_data = f.read()
            assert archived_data == filesystem_data, (
                f"Archived {ending} does not match the cleaned repository."
            )

        assert tar.extractfile(selected["v1/app.bin"]).read() == tar.extractfile(
            selected["v2/app.bin"]
        ).read(), "The archived duplicate binaries do not contain identical data."
        assert tar.extractfile(selected["v1/app.bin"]).read() != tar.extractfile(
            selected["v3/app.bin"]
        ).read(), "The archive does not preserve v3's distinct binary content."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
