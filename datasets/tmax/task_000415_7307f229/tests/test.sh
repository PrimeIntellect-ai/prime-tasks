#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import time
import uuid


def test_01_netmon_v1_killed():
    """Verify that no processes named netmon_v1 are running."""
    try:
        output = subprocess.check_output(["pgrep", "netmon_v1"]).decode("utf-8").strip()
        assert not output, f"netmon_v1 processes are still running: {output}"
    except subprocess.CalledProcessError:
        pass


def test_02_netmon_v2_compiled():
    """Verify that netmon_v2 is compiled in /home/user/."""
    path = "/home/user/netmon_v2"
    assert os.path.isfile(path), f"Compiled binary {path} is missing."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def check_original_stage(target_dir):
    assert os.path.isdir(target_dir), f"Directory {target_dir} was not created."

    binary_path = os.path.join(target_dir, "netmon_v2")
    assert os.path.isfile(binary_path), f"Binary {binary_path} was not copied."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."

    log_path = os.path.join(target_dir, "monitor.log")
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        log_content = f.read().strip().splitlines()

    expected_lines = [
        "[netadmin] 192.168.1.10 10.0.0.5",
        "[dbdaemon] 192.168.1.12 10.0.0.7",
        "[UNKNOWN] 192.168.1.13 10.0.0.8",
    ]
    assert len(log_content) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {log_path}, found {len(log_content)}."
    )
    for expected in expected_lines:
        assert expected in log_content, f"Expected line '{expected}' not found in {log_path}."


def test_03_stage_alpha_deployment():
    """Verify deployment in /home/user/stage_alpha."""
    check_original_stage("/home/user/stage_alpha")


def test_04_stage_beta_deployment():
    """Verify deployment in /home/user/stage_beta."""
    check_original_stage("/home/user/stage_beta")


def run_monitor(binary, conns, passwd):
    result = subprocess.run(
        [binary, conns, passwd],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"{binary} failed: {result.stderr}"
    return result.stdout.splitlines()


def test_05_sources_and_dynamic_parser_behavior():
    source = "/home/user/netmon.go"
    deploy = "/home/user/deploy.sh"
    submitted_binary = "/home/user/netmon_v2"

    assert os.path.isfile(source), f"Go source {source} is missing."
    assert os.path.isfile(deploy), f"Deployment script {deploy} is missing."
    assert os.access(deploy, os.X_OK), f"{deploy} is not executable."

    token = uuid.uuid4().hex[:10]
    known_user_a = "ops_" + token
    known_user_b = "svc_" + token
    uid_a = str(20000 + int(token[:3], 16) % 10000)
    uid_b = str(40000 + int(token[3:6], 16) % 10000)
    unknown_uid = str(60000 + int(token[6:9], 16) % 5000)

    rows = [
        ("172.19.11.7", "203.0.113.41", "ESTABLISHED", uid_b),
        ("172.19.11.8", "203.0.113.42", "LISTEN", uid_a),
        ("10.77.5.9", "198.51.100.17", "ESTABLISHED", unknown_uid),
        ("10.77.5.10", "198.51.100.18", "established", uid_a),
        ("192.0.2.25", "10.44.8.3", "ESTABLISHED", uid_a),
    ]
    users = {uid_a: known_user_a, uid_b: known_user_b}
    expected = [
        f"[{users.get(uid, 'UNKNOWN')}] {local_ip} {remote_ip}"
        for local_ip, remote_ip, status, uid in rows
        if status == "ESTABLISHED"
    ]

    with tempfile.TemporaryDirectory(prefix="netmon-parser-") as td:
        conns = os.path.join(td, "connections.csv")
        passwd = os.path.join(td, "passwd")
        rebuilt = os.path.join(td, "netmon_from_source")
        with open(conns, "w") as f:
            for row in rows:
                f.write(",".join(row) + "\n")
        with open(passwd, "w") as f:
            f.write(f"{known_user_a}:x:{uid_a}:1:A:/tmp:/bin/false\n")
            f.write(f"{known_user_b}:x:{uid_b}:1:B:/tmp:/bin/false\n")

        build = subprocess.run(
            ["go", "build", "-o", rebuilt, source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"netmon.go did not compile: {build.stderr}"

        assert run_monitor(rebuilt, conns, passwd) == expected
        assert run_monitor(submitted_binary, conns, passwd) == expected

        for binary in (rebuilt, submitted_binary):
            for args in ([], [conns], [conns, passwd, conns]):
                result = subprocess.run(
                    [binary] + args,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                assert result.returncode != 0, f"{binary} accepted {len(args)} arguments"


def test_06_deploy_script_with_varied_inputs_and_mounts():
    deploy = "/home/user/deploy.sh"
    home_binary = "/home/user/netmon_v2"
    config_paths = [
        "/home/user/conns.csv",
        "/home/user/mock_passwd",
        "/home/user/deploy_fstab",
    ]
    saved = {}
    for path in config_paths:
        with open(path, "rb") as f:
            saved[path] = f.read()

    token = uuid.uuid4().hex[:12]
    user_a = "blue_" + token
    user_b = "green_" + token
    uid_a = str(21000 + int(token[:4], 16) % 10000)
    uid_b = str(41000 + int(token[4:8], 16) % 10000)
    missing_uid = str(61000 + int(token[8:12], 16) % 4000)
    rows = [
        ("10.31.4.2", "192.0.2.77", "ESTABLISHED", uid_a),
        ("10.31.4.3", "192.0.2.78", "CLOSE_WAIT", uid_b),
        ("172.22.9.6", "198.51.100.88", "ESTABLISHED", missing_uid),
        ("172.22.9.7", "203.0.113.99", "ESTABLISHED", uid_b),
    ]
    users = {uid_a: user_a, uid_b: user_b}
    expected = [
        f"[{users.get(uid, 'UNKNOWN')}] {local_ip} {remote_ip}"
        for local_ip, remote_ip, status, uid in rows
        if status == "ESTABLISHED"
    ]

    work = tempfile.mkdtemp(prefix="netmon-deploy-")
    target_a = os.path.join(work, "mount one").replace(" ", "_")
    target_b = os.path.join(work, "second_target")
    legacy_path = os.path.join(work, "netmon_v1")
    legacy = None

    try:
        with open("/home/user/conns.csv", "w") as f:
            for row in rows:
                f.write(",".join(row) + "\n")
        with open("/home/user/mock_passwd", "w") as f:
            f.write(f"{user_a}:x:{uid_a}:7:A:/tmp:/bin/false\n")
            f.write(f"{user_b}:x:{uid_b}:8:B:/tmp:/bin/false\n")
        with open("/home/user/deploy_fstab", "w") as f:
            f.write("# dynamically generated deployment entries\n")
            f.write(f"tmpfs\t{target_a}\ttmpfs\trw,nosuid\t0\t0\n")
            f.write("   # an indented comment must be ignored\n")
            f.write(f"/dev/dynamic1   {target_b}   ext4   defaults   1   2\n")

        if os.path.lexists(home_binary):
            os.remove(home_binary)

        shutil.copy2("/bin/sleep", legacy_path)
        os.chmod(legacy_path, 0o755)
        legacy = subprocess.Popen([legacy_path, "3600"])
        time.sleep(0.15)
        assert legacy.poll() is None, "Failed to start the netmon_v1 test process"

        result = subprocess.run(
            [deploy],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"

        try:
            legacy.wait(timeout=5)
        except subprocess.TimeoutExpired:
            raise AssertionError("deploy.sh did not terminate the netmon_v1 process")

        assert os.path.isfile(home_binary), "deploy.sh did not compile /home/user/netmon_v2"
        assert os.access(home_binary, os.X_OK), "/home/user/netmon_v2 is not executable"
        with open(home_binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/netmon_v2 is not a compiled ELF binary"
        with open(home_binary, "rb") as f:
            home_bytes = f.read()

        assert run_monitor(home_binary, "/home/user/conns.csv", "/home/user/mock_passwd") == expected

        for target in (target_a, target_b):
            assert os.path.isdir(target), f"Deployment target {target} was not created"
            copied = os.path.join(target, "netmon_v2")
            log = os.path.join(target, "monitor.log")
            assert os.path.isfile(copied), f"{copied} was not copied"
            assert os.access(copied, os.X_OK), f"{copied} is not executable"
            with open(copied, "rb") as f:
                assert f.read() == home_bytes, f"{copied} is not a copy of the compiled binary"
            assert os.path.isfile(log), f"{log} was not created"
            with open(log, "r") as f:
                actual = f.read().splitlines()
            assert actual == expected, f"Unexpected output in {log}: {actual!r}"
    finally:
        if legacy is not None and legacy.poll() is None:
            legacy.kill()
            legacy.wait()
        for path, content in saved.items():
            with open(path, "wb") as f:
                f.write(content)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
