#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import time

DEPLOY_SCRIPT = "/home/user/deploy.py"
APP_SOURCE = "/home/user/app_source"
RELEASES_DIR = "/home/user/releases"
QUOTA = 204800


def reset_directories():
    shutil.rmtree(APP_SOURCE, ignore_errors=True)
    shutil.rmtree(RELEASES_DIR, ignore_errors=True)
    os.makedirs(APP_SOURCE, exist_ok=True)
    os.makedirs(RELEASES_DIR, exist_ok=True)


def create_dummy_file(size_kb):
    os.makedirs(APP_SOURCE, exist_ok=True)
    file_path = os.path.join(APP_SOURCE, "file1.bin")
    with open(file_path, "wb") as f:
        f.write(bytes(size_kb * 1024))


def run_deploy(version):
    result = subprocess.run(
        ["python3", DEPLOY_SCRIPT, version],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"deploy.py failed for {version}:\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def get_existing_releases():
    if not os.path.exists(RELEASES_DIR):
        return []
    items = os.listdir(RELEASES_DIR)
    return [
        item for item in items
        if item != "current" and os.path.isdir(os.path.join(RELEASES_DIR, item))
    ]


def assert_current(version):
    current_link = os.path.join(RELEASES_DIR, "current")
    assert os.path.islink(current_link), "'current' must be a symlink."
    target = os.readlink(current_link)
    assert os.path.basename(os.path.normpath(target)) == version, (
        f"'current' symlink does not point to {version}."
    )
    assert os.path.realpath(current_link) == os.path.realpath(
        os.path.join(RELEASES_DIR, version)
    )


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY_SCRIPT), f"Script {DEPLOY_SCRIPT} does not exist."
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"Script {DEPLOY_SCRIPT} is not executable."


def test_argument_count_handling():
    reset_directories()
    no_arg = subprocess.run(
        ["python3", DEPLOY_SCRIPT], capture_output=True, text=True
    )
    extra_arg = subprocess.run(
        ["python3", DEPLOY_SCRIPT, "one", "two"], capture_output=True, text=True
    )
    assert no_arg.returncode != 0, "deploy.py must reject a missing version argument."
    assert extra_arg.returncode != 0, "deploy.py must reject more than one argument."
    assert get_existing_releases() == [], "Invalid invocations must not create releases."


def test_copy_and_idempotent_update_with_runtime_version():
    reset_directories()
    version = "release-" + secrets.token_hex(8)
    root_data = os.urandom(4097)
    nested_data = os.urandom(733)

    with open(os.path.join(APP_SOURCE, "root.dat"), "wb") as f:
        f.write(root_data)
    os.makedirs(os.path.join(APP_SOURCE, "nested", "empty"))
    with open(os.path.join(APP_SOURCE, "nested", "payload.bin"), "wb") as f:
        f.write(nested_data)

    run_deploy(version)
    destination = os.path.join(RELEASES_DIR, version)
    assert os.path.isdir(destination)
    assert open(os.path.join(destination, "root.dat"), "rb").read() == root_data
    assert open(os.path.join(destination, "nested", "payload.bin"), "rb").read() == nested_data
    assert os.path.isdir(os.path.join(destination, "nested", "empty"))
    assert_current(version)

    updated_root = os.urandom(6151)
    added_data = os.urandom(997)
    with open(os.path.join(APP_SOURCE, "root.dat"), "wb") as f:
        f.write(updated_root)
    with open(os.path.join(APP_SOURCE, "nested", "added.bin"), "wb") as f:
        f.write(added_data)

    run_deploy(version)
    assert open(os.path.join(destination, "root.dat"), "rb").read() == updated_root
    assert open(os.path.join(destination, "nested", "payload.bin"), "rb").read() == nested_data
    assert open(os.path.join(destination, "nested", "added.bin"), "rb").read() == added_data
    assert_current(version)


def test_deployment_simulation():
    reset_directories()

    # Step 1: 80KB file, deploy v1
    create_dummy_file(80)
    run_deploy("v1")
    assert "v1" in get_existing_releases(), "v1 was not deployed correctly."
    assert os.path.getsize(os.path.join(RELEASES_DIR, "v1", "file1.bin")) == 80 * 1024

    # Step 2: deploy v2
    time.sleep(1.1)
    run_deploy("v2")
    releases = get_existing_releases()
    assert "v1" in releases and "v2" in releases, "v1 and v2 should exist."
    assert os.path.getsize(os.path.join(RELEASES_DIR, "v2", "file1.bin")) == 80 * 1024

    # Step 3: deploy v3, should delete v1 (80*3 = 240 > 200)
    time.sleep(1.1)
    run_deploy("v3")
    releases = get_existing_releases()
    assert "v1" not in releases, "v1 should have been deleted to enforce quota."
    assert "v2" in releases and "v3" in releases, "v2 and v3 should exist."
    assert os.path.getsize(os.path.join(RELEASES_DIR, "v3", "file1.bin")) == 80 * 1024

    # Step 4: 250KB file, deploy v4
    create_dummy_file(250)
    time.sleep(1.1)
    run_deploy("v4")
    releases = get_existing_releases()
    assert "v2" not in releases, "v2 should have been deleted."
    assert "v3" not in releases, "v3 should have been deleted."
    assert "v4" in releases, "v4 must exist as it is the current release."
    assert os.path.getsize(os.path.join(RELEASES_DIR, "v4", "file1.bin")) == 250 * 1024

    # Check symlink
    current_link = os.path.join(RELEASES_DIR, "current")
    assert os.path.islink(current_link), "'current' must be a symlink."
    target = os.readlink(current_link)
    assert os.path.basename(os.path.normpath(target)) == "v4", "'current' symlink does not point to v4."


def test_randomized_quota_mtime_order_and_current_exception():
    reset_directories()
    versions = ["q-" + secrets.token_hex(7) for _ in range(4)]
    payload = os.urandom(80 * 1024)
    with open(os.path.join(APP_SOURCE, "quota_payload.bin"), "wb") as f:
        f.write(payload)

    run_deploy(versions[0])
    run_deploy(versions[1])
    assert set(get_existing_releases()) == set(versions[:2])

    # Make the second-deployed release older by directory mtime. It must be
    # removed first even though it was deployed after versions[0].
    now = time.time()
    os.utime(os.path.join(RELEASES_DIR, versions[0]), (now - 100, now - 100))
    os.utime(os.path.join(RELEASES_DIR, versions[1]), (now - 300, now - 300))

    run_deploy(versions[2])
    releases = get_existing_releases()
    assert versions[1] not in releases, "The release with the oldest mtime was not deleted."
    assert versions[0] in releases and versions[2] in releases
    assert open(os.path.join(RELEASES_DIR, versions[2], "quota_payload.bin"), "rb").read() == payload
    assert_current(versions[2])

    # An oversized current release must survive even when the quota cannot be met.
    oversized = os.urandom(250 * 1024)
    with open(os.path.join(APP_SOURCE, "quota_payload.bin"), "wb") as f:
        f.write(oversized)
    run_deploy(versions[3])
    releases = get_existing_releases()
    assert releases == [versions[3]] or set(releases) == {versions[3]}
    assert open(os.path.join(RELEASES_DIR, versions[3], "quota_payload.bin"), "rb").read() == oversized
    assert os.path.getsize(os.path.join(RELEASES_DIR, versions[3], "quota_payload.bin")) > QUOTA
    assert_current(versions[3])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
