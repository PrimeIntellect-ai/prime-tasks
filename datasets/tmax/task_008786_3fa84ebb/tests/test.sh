#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import time

import pytest

BASE = "/home/user/backup_op"
SCRIPT = os.path.join(BASE, "run_pipeline.sh")
SERVICE = os.path.join(BASE, "storage_service/target/release/storage_service")
CLIENT = os.path.join(BASE, "restore_client/target/release/restore_client")
LOG = os.path.join(BASE, "restore_success.log")


@pytest.fixture(scope="session", autouse=True)
def execute_fresh_pipeline():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"Script {SCRIPT} is not executable."

    subprocess.run(["pkill", "-x", "storage_service"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    for target in (
        os.path.join(BASE, "storage_service/target"),
        os.path.join(BASE, "restore_client/target"),
    ):
        shutil.rmtree(target, ignore_errors=True)
    if os.path.exists(LOG):
        os.remove(LOG)

    try:
        result = subprocess.run(
            [SCRIPT], cwd=BASE, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=300
        )
    except subprocess.TimeoutExpired:
        subprocess.run(["pkill", "-x", "storage_service"], check=False)
        pytest.fail("run_pipeline.sh did not finish within 300 seconds")

    lingering = subprocess.run(
        ["pgrep", "-x", "storage_service"], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    ).returncode == 0
    if lingering:
        subprocess.run(["pkill", "-x", "storage_service"], check=False)

    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert not lingering, "run_pipeline.sh left storage_service running instead of killing it"

    for binary in (SERVICE, CLIENT):
        assert os.path.isfile(binary), f"Pipeline did not build {binary}"
        assert os.access(binary, os.X_OK), f"Built artifact {binary} is not executable"
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Built artifact {binary} is not an ELF executable"


def test_users_json_exists_and_valid():
    users_file = "/home/user/backup_op/users.json"
    assert os.path.isfile(users_file), f"File {users_file} does not exist."

    with open(users_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {users_file} does not contain valid JSON.")

    assert "users" in data, f"'users' key missing in {users_file}"
    assert len(data["users"]) > 0, f"'users' list is empty in {users_file}"

    user_obj = data["users"][0]
    assert user_obj.get("username") == "backup_agent", "Username should be 'backup_agent'."
    assert user_obj.get("group") == "system_admins", "Group should be 'system_admins'."
    assert user_obj.get("token") == "pipeline-token-883", "Token should be 'pipeline-token-883'."


def test_restore_client_ip_fixed():
    main_rs = "/home/user/backup_op/restore_client/src/main.rs"
    assert os.path.isfile(main_rs), f"File {main_rs} does not exist."

    with open(main_rs, 'r') as f:
        content = f.read()

    assert "127.0.0.2:9090" in content, f"The IP address in {main_rs} was not updated to 127.0.0.2:9090."
    assert "127.0.0.1:9090" not in content, f"The old IP address 127.0.0.1:9090 is still present in {main_rs}."


def test_run_pipeline_script_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        assert f.readline().rstrip(b"\r\n") == b"#!/bin/bash", "run_pipeline.sh must start with #!/bin/bash"


def test_restore_success_log():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist. Did you run the pipeline script?"
    with open(LOG, 'r') as f:
        content = f.read()
    assert "BACKUP_DATA_RESTORED_V1" in content, f"The expected success payload 'BACKUP_DATA_RESTORED_V1' was not found in {LOG}."


def test_built_components_authorize_real_requests():
    service = subprocess.Popen(
        [SERVICE], cwd=os.path.join(BASE, "storage_service"),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
    )
    try:
        valid = None
        for _ in range(30):
            valid = subprocess.run(
                [CLIENT, "--token", "pipeline-token-883"], cwd=BASE,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            if valid.returncode == 0:
                break
            if service.poll() is not None:
                pytest.fail(f"storage_service exited early: {service.stderr.read()}")
            time.sleep(0.1)

        assert valid is not None and valid.returncode == 0, (
            f"restore_client could not connect to storage_service: {valid.stderr if valid else ''}"
        )
        assert valid.stdout.strip() == "BACKUP_DATA_RESTORED_V1", (
            f"Valid credentials produced unexpected response: {valid.stdout!r}"
        )

        invalid_token = "invalid-" + secrets.token_hex(16)
        invalid = subprocess.run(
            [CLIENT, "--token", invalid_token], cwd=BASE,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert invalid.returncode == 0, f"restore_client failed on an invalid-token request: {invalid.stderr}"
        assert invalid.stdout.strip() == "UNAUTHORIZED", (
            f"Storage service accepted a verifier-generated invalid token: {invalid.stdout!r}"
        )
    finally:
        if service.poll() is None:
            service.terminate()
            try:
                service.wait(timeout=5)
            except subprocess.TimeoutExpired:
                service.kill()
                service.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
