#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import subprocess
import tempfile
import uuid


def run_binary(binary_path, config_path):
    result = subprocess.run(
        [binary_path, config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{binary_path} failed with exit code {result.returncode}: {result.stderr}"
    )


def exercise_fstab_parser(binary_path):
    with tempfile.TemporaryDirectory(prefix="logdaemon-test-") as temp_dir:
        mount_point = os.path.join(temp_dir, "resolved-logs")
        os.mkdir(mount_point)
        config_path = os.path.join(temp_dir, "fstab.conf")
        with open(config_path, "w") as f:
            f.write("UUID=UNRELATED /should/not/be/used ext4 defaults 0 2\n")
            f.write("# UUID=APP_LOGS /also/not/used ext4 defaults 0 2\n")
            f.write(f"UUID=APP_LOGS\t{mount_point}\text4 defaults 0 2\n")

        run_binary(binary_path, config_path)
        output_path = os.path.join(mount_point, "daemon.log")
        assert os.path.isfile(output_path), (
            "The binary did not create daemon.log in the mount point selected "
            "from the UUID=APP_LOGS line"
        )
        with open(output_path, "rb") as f:
            assert f.read() == b"DEPLOYMENT_V2_SUCCESS"


def test_binary_and_symlink():
    binary_path = "/home/user/deploy/releases/v2/logdaemon"
    symlink_path = "/home/user/deploy/current"

    assert os.path.exists(binary_path), f"Binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Deployed logdaemon is not a compiled ELF binary"
    build_info = subprocess.run(
        ["go", "version", "-m", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert build_info.returncode == 0 and "go1." in build_info.stdout, (
        "Deployed logdaemon does not contain Go build information"
    )

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    target = os.readlink(symlink_path)
    assert target == "/home/user/deploy/releases/v2", f"Symlink points to {target}, expected /home/user/deploy/releases/v2"


def test_fstab_configuration():
    fstab_path = "/home/user/deploy/config/fstab.conf"
    assert os.path.exists(fstab_path), f"fstab config not found at {fstab_path}"

    with open(fstab_path, "r") as f:
        content = f.read()

    assert "UUID=APP_LOGS" in content, "UUID=APP_LOGS not found in fstab.conf"
    assert "/home/user/deploy/logs" in content, "Mount point /home/user/deploy/logs not found in fstab.conf"
    expected = ["UUID=APP_LOGS", "/home/user/deploy/logs", "ext4", "defaults", "0", "2"]
    assert any(line.split() == expected for line in content.splitlines()), (
        "fstab.conf does not contain the required complete UUID=APP_LOGS entry"
    )
    assert os.path.isdir("/home/user/deploy/logs"), "Required log directory does not exist"


def test_logrotate_configuration():
    logrotate_path = "/home/user/deploy/config/logrotate.conf"
    assert os.path.exists(logrotate_path), f"logrotate config not found at {logrotate_path}"

    with open(logrotate_path, "r") as f:
        content = f.read()

    assert "size 10" in content, "'size 10' directive missing in logrotate.conf"
    assert "rotate 3" in content, "'rotate 3' directive missing in logrotate.conf"
    assert "compress" in content, "'compress' directive missing in logrotate.conf"
    assert "missingok" in content, "'missingok' directive missing in logrotate.conf"


def test_log_rotation_and_contents():
    rotated_log_path = "/home/user/deploy/logs/daemon.log.1.gz"
    assert os.path.exists(rotated_log_path), f"Rotated log file not found at {rotated_log_path}. Did logrotate run successfully?"

    with gzip.open(rotated_log_path, "rt") as f:
        content = f.read()

    assert "DEPLOYMENT_V2_SUCCESS" in content, "The expected string 'DEPLOYMENT_V2_SUCCESS' was not found in the rotated log file."


def test_deployed_binary_executes_and_parses_fstab():
    binary_via_symlink = "/home/user/deploy/current/logdaemon"
    exercise_fstab_parser(binary_via_symlink)

    canonical_log = "/home/user/deploy/logs/daemon.log"
    if os.path.lexists(canonical_log):
        os.unlink(canonical_log)
    run_binary(binary_via_symlink, "/home/user/deploy/config/fstab.conf")
    with open(canonical_log, "rb") as f:
        assert f.read() == b"DEPLOYMENT_V2_SUCCESS", (
            "Running the deployed binary with the submitted fstab did not create "
            "the required daemon.log contents"
        )


def test_main_go_builds_and_implements_behavior():
    source_path = "/home/user/workspace/main.go"
    assert os.path.isfile(source_path), f"Go source not found at {source_path}"

    with tempfile.TemporaryDirectory(prefix="go-build-test-") as temp_dir:
        rebuilt_path = os.path.join(temp_dir, "logdaemon")
        result = subprocess.run(
            ["go", "build", "-o", rebuilt_path, source_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"main.go does not compile: {result.stderr}"
        exercise_fstab_parser(rebuilt_path)


def test_logrotate_config_actually_rotates_and_compresses():
    log_dir = "/home/user/deploy/logs"
    live_log = os.path.join(log_dir, "daemon.log")
    for path in glob.glob(os.path.join(log_dir, "daemon.log.*")):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    if os.path.lexists(live_log):
        os.unlink(live_log)

    marker = "ROTATE_" + uuid.uuid4().hex
    payload = marker + "0123456789" * 6
    with open(live_log, "w") as f:
        f.write(payload)

    state_path = os.path.join(tempfile.gettempdir(), "logrotate-state-" + uuid.uuid4().hex)
    result = subprocess.run(
        ["logrotate", "-f", "-s", state_path, "/home/user/deploy/config/logrotate.conf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"logrotate failed using the submitted config: {result.stderr}"

    rotated_log_path = live_log + ".1.gz"
    assert os.path.isfile(rotated_log_path), (
        "Running logrotate did not create daemon.log.1.gz"
    )
    with gzip.open(rotated_log_path, "rt") as f:
        rotated_content = f.read()
    assert marker in rotated_content, (
        "The freshly generated content was not rotated and compressed by logrotate"
    )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
