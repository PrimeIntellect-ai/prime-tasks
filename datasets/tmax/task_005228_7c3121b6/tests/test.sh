#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tarfile

SCRIPT_PATH = "/home/user/config_archiver.py"
CONFIG_ROOT = "/home/user/configs"
RAW_ROOT = CONFIG_ROOT + "/raw"
ARCHIVE_PATH = CONFIG_ROOT + "/archive/active_configs.tar.gz"
SYMLINK_PATH = CONFIG_ROOT + "/latest.tar.gz"
HARDLINK_PATH = CONFIG_ROOT + "/latest_valid_raw.cfg"
MAGIC = b"\xCF\xFA\xED\xFE"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script at {SCRIPT_PATH} does not exist."


def test_archive_exists_and_contents():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."

    expected_files = {"app_v05.cfg", "app_v10.cfg", "app_v15.cfg"}
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getnames()
        actual_files = set(members)
        assert actual_files == expected_files, f"Archive contents mismatch. Expected {expected_files}, got {actual_files}. Make sure files are stored at the root of the archive without full paths."
        assert len(members) == len(expected_files), "Archive contains duplicate entries."
        for filename in expected_files:
            member = tar.getmember(filename)
            assert member.isfile(), f"Archive member {filename} is not a regular file."
            archived = tar.extractfile(member)
            assert archived is not None
            with open(os.path.join(RAW_ROOT, filename), "rb") as raw_file:
                expected_bytes = raw_file.read()
            assert archived.read() == expected_bytes, f"Archived bytes for {filename} differ from the raw file."


def test_symlink_latest_archive():
    assert os.path.islink(SYMLINK_PATH), f"{SYMLINK_PATH} is not a symbolic link."
    resolved_target = os.path.realpath(SYMLINK_PATH)
    expected_target = os.path.realpath(ARCHIVE_PATH)
    assert resolved_target == expected_target, f"Symlink {SYMLINK_PATH} points to {resolved_target}, expected it to point to {expected_target}."


def test_hardlink_latest_valid_raw():
    target_path = os.path.join(RAW_ROOT, "app_v15.cfg")
    assert os.path.isfile(HARDLINK_PATH), f"Hard link {HARDLINK_PATH} does not exist."
    assert os.path.isfile(target_path), f"Target file {target_path} does not exist."
    link_stat = os.stat(HARDLINK_PATH)
    target_stat = os.stat(target_path)
    assert link_stat.st_ino == target_stat.st_ino, f"{HARDLINK_PATH} is not a hard link to {target_path} (inodes do not match)."
    assert link_stat.st_dev == target_stat.st_dev, f"{HARDLINK_PATH} and {target_path} are on different devices."


def test_original_files_unmodified():
    expected_files = {
        "app_v10.cfg": (0o644, MAGIC + b"VERSION: 10\nkey=value\n"),
        "app_v15.cfg": (0o644, MAGIC + b"VERSION: 15\nkey=value\n"),
        "app_v05.cfg": (0o644, MAGIC + b"VERSION: 5\nkey=value\n"),
        "app_v20_badperms.cfg": (0o600, MAGIC + b"VERSION: 20\nkey=value\n"),
        "app_v30_badhead.cfg": (0o644, b"\x00\x00\x00\x00VERSION: 30\nkey=value\n"),
    }

    for filename, (expected_perms, expected_bytes) in expected_files.items():
        filepath = os.path.join(RAW_ROOT, filename)
        assert os.path.isfile(filepath), f"Original file {filepath} is missing. The script should not remove original files."
        actual_perms = stat.S_IMODE(os.stat(filepath).st_mode)
        assert actual_perms == expected_perms, f"Original file {filepath} permissions were modified."
        with open(filepath, "rb") as f:
            assert f.read() == expected_bytes, f"Original file {filepath} contents were modified."


def test_script_behavior_on_derived_inputs():
    token = secrets.token_hex(8)
    backup_root = f"/home/user/.verifier-configs-backup-{token}"
    os.rename(CONFIG_ROOT, backup_root)

    try:
        os.makedirs(RAW_ROOT)
        os.makedirs(os.path.dirname(ARCHIVE_PATH))

        base = 1000 + secrets.randbelow(100000)
        valid_specs = {
            f"cfg_{token}_a.cfg": (base + 7, b"alpha=" + token.encode() + b"\n"),
            f"cfg_{token}_b.cfg": (base + 41, b"beta=two\nextra=data\n"),
            f"cfg_{token}_c.cfg": (base + 19, b"gamma=three\n"),
        }
        excluded_specs = {
            f"cfg_{token}_badmode.cfg": (MAGIC + f"VERSION: {base + 900}\nexcluded=mode\n".encode(), 0o600),
            f"cfg_{token}_badmagic.cfg": (b"\x00\x00\x00\x00" + f"VERSION: {base + 901}\nexcluded=magic\n".encode(), 0o644),
        }

        expected_bytes = {}
        for name, (version, body) in valid_specs.items():
            data = MAGIC + f"VERSION: {version}\n".encode() + body
            path = os.path.join(RAW_ROOT, name)
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, 0o644)
            expected_bytes[name] = data

        for name, (data, mode) in excluded_specs.items():
            path = os.path.join(RAW_ROOT, name)
            with open(path, "wb") as f:
                f.write(data)
            os.chmod(path, mode)

        before = {}
        for name in os.listdir(RAW_ROOT):
            path = os.path.join(RAW_ROOT, name)
            st = os.stat(path)
            with open(path, "rb") as f:
                data = f.read()
            before[name] = (st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode), st.st_mtime_ns, data)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            text=True,
        )
        assert result.returncode == 0, f"Script failed on verification inputs. stdout={result.stdout!r} stderr={result.stderr!r}"

        assert os.path.isfile(ARCHIVE_PATH), "Script did not create the archive when executed."
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            members = tar.getmembers()
            assert [m.name for m in members] == list(dict.fromkeys(m.name for m in members)), "Archive contains duplicate entries."
            assert {m.name for m in members} == set(valid_specs), "Executed script archived the wrong dynamically generated files."
            for member in members:
                assert member.name == os.path.basename(member.name), f"Archive member {member.name} is not stored at the archive root."
                assert member.isfile(), f"Archive member {member.name} is not a regular file."
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == expected_bytes[member.name], f"Archive member {member.name} does not contain the raw file's bytes."

        assert os.path.islink(SYMLINK_PATH), "Executed script did not create latest.tar.gz as a symbolic link."
        assert os.path.realpath(SYMLINK_PATH) == os.path.realpath(ARCHIVE_PATH), "Executed script created latest.tar.gz with the wrong target."

        highest_name = max(valid_specs, key=lambda name: valid_specs[name][0])
        highest_path = os.path.join(RAW_ROOT, highest_name)
        assert os.path.isfile(HARDLINK_PATH), "Executed script did not create latest_valid_raw.cfg."
        link_stat = os.stat(HARDLINK_PATH)
        target_stat = os.stat(highest_path)
        assert (link_stat.st_dev, link_stat.st_ino) == (target_stat.st_dev, target_stat.st_ino), "Executed script did not hard-link the highest-version valid raw file."

        assert set(os.listdir(RAW_ROOT)) == set(before), "Executed script added or removed raw files."
        for name, old_state in before.items():
            path = os.path.join(RAW_ROOT, name)
            st = os.stat(path)
            with open(path, "rb") as f:
                data = f.read()
            new_state = (st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode), st.st_mtime_ns, data)
            assert new_state == old_state, f"Executed script modified raw file {name}."
    finally:
        if os.path.lexists(CONFIG_ROOT):
            if os.path.isdir(CONFIG_ROOT) and not os.path.islink(CONFIG_ROOT):
                shutil.rmtree(CONFIG_ROOT)
            else:
                os.unlink(CONFIG_ROOT)
        os.rename(backup_root, CONFIG_ROOT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
