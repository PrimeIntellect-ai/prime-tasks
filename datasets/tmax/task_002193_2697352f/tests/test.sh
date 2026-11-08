#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import pwd
import shutil
import subprocess
import tempfile


def run_as_user(command):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env["HOME"] = account.pw_dir
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
        cwd=account.pw_dir,
        env=env,
        preexec_fn=demote,
    )


def test_archiver_and_extractor():
    archive_script = "/home/user/archive.py"
    extract_script = "/home/user/extract.py"

    assert os.path.exists(archive_script), f"{archive_script} does not exist"
    assert os.path.exists(extract_script), f"{extract_script} does not exist"
    assert os.path.isfile(archive_script), f"{archive_script} is not a regular file"
    assert os.path.isfile(extract_script), f"{extract_script} is not a regular file"

    configs_dir = "/home/user/configs"
    archive_file = "/home/user/archive.bin"
    restored_dir = "/home/user/restored"

    if os.path.exists(archive_file):
        os.remove(archive_file)
    if os.path.exists(restored_dir):
        shutil.rmtree(restored_dir)

    os.makedirs(restored_dir, exist_ok=True)
    account = pwd.getpwnam("user")
    os.chown(restored_dir, account.pw_uid, account.pw_gid)

    hidden_parent = None
    hidden_configs = None
    try:
        # 1. Run archiver against the original input directory.
        try:
            run_as_user(["python3", archive_script, configs_dir, archive_file])
        except subprocess.CalledProcessError as e:
            assert False, f"archive.py failed with error:\n{e.stderr}"

        assert os.path.exists(archive_file), f"Archive file {archive_file} was not created."
        assert os.path.isfile(archive_file), f"Archive path {archive_file} is not a regular file."

        # Hide the source in a root-only directory before extraction. The extractor
        # must reconstruct from the archive rather than copy /home/user/configs.
        hidden_parent = tempfile.mkdtemp(prefix="archiver-source-", dir="/root")
        os.chmod(hidden_parent, 0o700)
        hidden_configs = os.path.join(hidden_parent, "configs")
        shutil.move(configs_dir, hidden_configs)

        # 2. Run extractor without privileges that could access the hidden source.
        try:
            run_as_user(["python3", extract_script, archive_file, restored_dir])
        except subprocess.CalledProcessError as e:
            assert False, f"extract.py failed with error:\n{e.stderr}"

        # 3. Verify exact match against the root-only original.
        orig_files = sorted(os.listdir(hidden_configs))
        restored_files = sorted(os.listdir(restored_dir))
        assert orig_files == restored_files, "Restored file list does not match original."

        for f in orig_files:
            orig_path = os.path.join(hidden_configs, f)
            rest_path = os.path.join(restored_dir, f)
            assert filecmp.cmp(orig_path, rest_path, shallow=False), f"Restored file {f} differs from original."

        # 4. Compute metric.
        archive_size = os.path.getsize(archive_file)
        assert archive_size < 2000000, f"Archive size is {archive_size} bytes, which is not less than the 2000000 bytes threshold."
    finally:
        # Restore the fixture for clean teardown even if an assertion fails.
        if hidden_configs is not None and os.path.exists(hidden_configs):
            if os.path.lexists(configs_dir):
                if os.path.isdir(configs_dir) and not os.path.islink(configs_dir):
                    shutil.rmtree(configs_dir)
                else:
                    os.remove(configs_dir)
            shutil.move(hidden_configs, configs_dir)
        if hidden_parent is not None and os.path.exists(hidden_parent):
            shutil.rmtree(hidden_parent)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
