#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tarfile

SCRIPT_PATH = "/home/user/migrate_configs.sh"
ARCHIVE_PATH = "/home/user/migrated_configs.tar.gz"
MANIFEST_PATH = "/home/user/migration_manifest.txt"
EXTRACTED_DIR = "/home/user/extracted_configs"
ORGANIZED_DIR = "/home/user/organized_configs"
OLD_ENDPOINT = b"API_ENDPOINT=http://old.internal/api"
NEW_ENDPOINT = b"API_ENDPOINT=https://new.internal.corp/v2/api"


def expected_original(i):
    year = 2020 + (i % 4)
    month = (i % 12) + 1
    day = (i % 28) + 1
    return (
        f"SERVER_ID=server_{i:03d}\n"
        f"BIND_IP=10.0.0.{i}\n"
        "API_ENDPOINT=http://old.internal/api\n"
        f"TIMESTAMP={year}-{month:02d}-{day:02d}\n"
    ).encode("utf-8")


def expected_files():
    result = {}
    for i in range(1, 101):
        year = 2020 + (i % 4)
        month = (i % 12) + 1
        path = f"{year}/{month:02d}/server_{i:03d}.conf"
        result[path] = expected_original(i).replace(OLD_ENDPOINT, NEW_ENDPOINT)
    return result


def get_expected_paths():
    paths = list(expected_files())
    paths.sort()
    return paths


def check_final_artifacts():
    # Keep the original script existence and executable assertions.
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"Script {SCRIPT_PATH} is not a regular file."

    # Keep the original manifest assertions.
    assert os.path.isfile(MANIFEST_PATH), f"Manifest {MANIFEST_PATH} does not exist."
    with open(MANIFEST_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_paths = get_expected_paths()
    assert len(lines) == 100, f"Manifest should contain exactly 100 lines, found {len(lines)}."
    assert lines == expected_paths, "Manifest contents do not match the expected sorted paths."

    # Keep the original archive/path/endpoint assertions and additionally verify
    # every migrated file byte-for-byte apart from the required replacement.
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"{ARCHIVE_PATH} is not a valid tar archive."
    expected = expected_files()
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        member_names = sorted(m.name for m in members)
        assert member_names == expected_paths, (
            "The paths inside the tar archive do not match the expected "
            "YYYY/MM/server_XXX.conf structure."
        )
        for member in members:
            f = tar.extractfile(member)
            assert f is not None
            data = f.read()
            content = data.decode("utf-8")
            assert "API_ENDPOINT=https://new.internal.corp/v2/api" in content, (
                f"File {member.name} does not contain the updated API_ENDPOINT."
            )
            assert "http://old.internal/api" not in content, (
                f"File {member.name} still contains the old API_ENDPOINT."
            )
            assert data == expected[member.name], (
                f"File {member.name} does not preserve the original configuration "
                "with only the required endpoint migration."
            )


def prepare_clean_script_input():
    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    shutil.rmtree(ORGANIZED_DIR, ignore_errors=True)
    os.makedirs(EXTRACTED_DIR, mode=0o755)
    os.makedirs(ORGANIZED_DIR, mode=0o755)
    os.chown(EXTRACTED_DIR, 1000, 1000)
    os.chown(ORGANIZED_DIR, 1000, 1000)

    for i in range(1, 101):
        path = os.path.join(EXTRACTED_DIR, f"server_{i:03d}.conf")
        with open(path, "wb") as f:
            f.write(expected_original(i))
        os.chown(path, 1000, 1000)
        os.chmod(path, 0o644)


def check_script_behavior():
    # Exercise the submitted Bash script on a fresh, verifier-controlled copy of
    # all inputs. Clearing organized_configs ensures an executable no-op cannot pass.
    prepare_clean_script_input()
    result = subprocess.run(
        ["runuser", "--user", "user", "--", "/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Migration script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    expected = expected_files()
    actual_paths = []
    for root, dirs, files in os.walk(ORGANIZED_DIR):
        for name in files:
            full_path = os.path.join(root, name)
            rel_path = os.path.relpath(full_path, ORGANIZED_DIR).replace(os.sep, "/")
            actual_paths.append(rel_path)
            assert not os.path.islink(full_path), f"Organized file {rel_path} is a symlink."
            with open(full_path, "rb") as f:
                data = f.read()
            assert data == expected.get(rel_path), (
                f"Script produced incorrect path or content for {rel_path}."
            )

    assert sorted(actual_paths) == sorted(expected), (
        "Running the script on clean inputs did not create exactly the required "
        "100 organized configuration files."
    )

    remaining_conf = []
    for root, dirs, files in os.walk(EXTRACTED_DIR):
        for name in files:
            if name.endswith(".conf"):
                remaining_conf.append(os.path.join(root, name))
    assert not remaining_conf, "The script did not move all .conf files out of extracted_configs."


def test_final_state_and_script_behavior():
    check_final_artifacts()
    check_script_behavior()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
