#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import textwrap

SCRIPT = "/home/user/generate_operator_config.py"
FSTAB = "/home/user/mock_fstab"


def run_generator():
    result = subprocess.run(
        ["python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Generator failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_manifest(mount_point):
    basename = os.path.basename(mount_point.rstrip("/"))
    return textwrap.dedent(f"""\
        apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: local-ext4-{basename}
        spec:
          storageClassName: manual
          local:
            path: {mount_point}
    """).strip()


def test_00_execute_student_generator_from_clean_state():
    assert os.path.isfile(SCRIPT), f"Student script {SCRIPT} does not exist."

    operator_path = "/home/user/operator"
    if os.path.lexists(operator_path):
        if os.path.islink(operator_path) or not os.path.isdir(operator_path):
            os.unlink(operator_path)
        else:
            shutil.rmtree(operator_path)

    env_script = "/home/user/operator_env.sh"
    if os.path.lexists(env_script):
        if os.path.isdir(env_script) and not os.path.islink(env_script):
            shutil.rmtree(env_script)
        else:
            os.unlink(env_script)

    run_generator()


def test_operator_env_script():
    env_script = "/home/user/operator_env.sh"
    assert os.path.isfile(env_script), f"File {env_script} does not exist."

    with open(env_script, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = ["export TZ=UTC", "export LANG=C.UTF-8"]
    assert content == expected_lines, f"Content of {env_script} is incorrect. Expected {expected_lines}, got {content}"


def test_directory_and_symlink():
    manifests_dir = "/home/user/operator/manifests/v1"
    active_symlink = "/home/user/operator/active"

    assert os.path.isdir(manifests_dir), f"Directory {manifests_dir} does not exist."
    assert os.path.islink(active_symlink), f"{active_symlink} is not a symlink."

    target = os.readlink(active_symlink)
    assert target == "/home/user/operator/manifests/v1", f"Symlink {active_symlink} points to {target}, expected /home/user/operator/manifests/v1"


def test_pv_manifests_generated():
    pv_storage = "/home/user/operator/active/pv-storage.yaml"
    pv_db_disk = "/home/user/operator/active/pv-db_disk.yaml"

    assert os.path.isfile(pv_storage), f"Manifest {pv_storage} does not exist."
    assert os.path.isfile(pv_db_disk), f"Manifest {pv_db_disk} does not exist."

    expected_storage = textwrap.dedent("""\
        apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: local-ext4-storage
        spec:
          storageClassName: manual
          local:
            path: /mnt/storage
    """).strip()

    expected_db_disk = textwrap.dedent("""\
        apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: local-ext4-db_disk
        spec:
          storageClassName: manual
          local:
            path: /data/db_disk
    """).strip()

    with open(pv_storage, "r") as f:
        storage_content = f.read().strip()
    assert storage_content == expected_storage, f"Content of {pv_storage} is incorrect."

    with open(pv_db_disk, "r") as f:
        db_disk_content = f.read().strip()
    assert db_disk_content == expected_db_disk, f"Content of {pv_db_disk} is incorrect."


def test_student_script_exists():
    script_path = "/home/user/generate_operator_config.py"
    assert os.path.isfile(script_path), f"Student script {script_path} does not exist."


def test_z_dynamic_fstab_parsing_and_idempotence():
    entries = [
        ("/dev/test-a", "/dynamic/alpha_volume", "ext4", "defaults", "0", "2"),
        ("server:/share", "/dynamic/skip_nfs", "nfs", "defaults", "0", "0"),
        ("/dev/test-b", "/srv/data/beta-disk", "ext4", "ro,nosuid", "0", "1"),
    ]
    dynamic_fstab = (
        "# dynamically supplied verifier input\n"
        "\n"
        + "   \t".join(entries[0]) + "\n"
        + "\t".join(entries[1]) + "\n"
        + "  ".join(entries[2]) + "\n"
    )

    with open(FSTAB, "rb") as f:
        original_fstab = f.read()

    ext4_outputs = []
    for _, mount_point, fs_type, _, _, _ in entries:
        output = f"/home/user/operator/active/pv-{os.path.basename(mount_point)}.yaml"
        if os.path.lexists(output):
            os.unlink(output)
        if fs_type == "ext4":
            ext4_outputs.append((output, mount_point))

    non_ext4_output = "/home/user/operator/active/pv-skip_nfs.yaml"

    try:
        with open(FSTAB, "w") as f:
            f.write(dynamic_fstab)

        run_generator()

        first_contents = {}
        for output, mount_point in ext4_outputs:
            assert os.path.isfile(output), f"Dynamic ext4 manifest {output} was not generated."
            with open(output, "r") as f:
                content = f.read().strip()
            assert content == expected_manifest(mount_point), f"Content of dynamic manifest {output} is incorrect."
            first_contents[output] = content

        assert not os.path.lexists(non_ext4_output), "A manifest was incorrectly generated for a non-ext4 entry."
        assert os.path.isdir("/home/user/operator/manifests/v1")
        assert os.path.islink("/home/user/operator/active")
        assert os.readlink("/home/user/operator/active") == "/home/user/operator/manifests/v1"

        with open("/home/user/operator_env.sh", "r") as f:
            first_env = f.read()

        run_generator()

        assert os.path.isdir("/home/user/operator/manifests/v1")
        assert os.path.islink("/home/user/operator/active")
        assert os.readlink("/home/user/operator/active") == "/home/user/operator/manifests/v1"
        with open("/home/user/operator_env.sh", "r") as f:
            assert f.read() == first_env
        for output, _ in ext4_outputs:
            with open(output, "r") as f:
                assert f.read().strip() == first_contents[output]
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
