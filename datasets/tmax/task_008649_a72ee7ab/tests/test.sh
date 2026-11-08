#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import stat
import subprocess
import uuid


def test_nginx_config_backup():
    bak_path = "/home/user/nginx/nginx.conf.bak"
    assert os.path.isfile(bak_path), f"Backup file missing: {bak_path}"
    with open(bak_path, 'r') as f:
        content = f.read()
    assert "8081" in content, "Backup file does not contain the original port 8081"


def test_nginx_config_updated():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing: {conf_path}"
    with open(conf_path, 'r') as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in content, "Nginx config does not contain the updated port 8080"


def test_storage_quota_backup():
    bak_path = "/home/user/backend/data.db.bak"
    assert os.path.isfile(bak_path), f"Database backup missing: {bak_path}"
    size = os.path.getsize(bak_path)
    expected_size = 2 * 1024 * 1024
    assert size == expected_size, f"Database backup size is {size}, expected {expected_size} bytes"


def test_storage_quota_original():
    db_path = "/home/user/backend/data.db"
    if os.path.exists(db_path):
        size = os.path.getsize(db_path)
        assert size <= 1024 * 1024, f"Database file is too large: {size} bytes (must be <= 1MB)"


def test_timezone_profile():
    env_path = "/home/user/.backend_env"
    assert os.path.isfile(env_path), f"Environment profile missing: {env_path}"
    with open(env_path, 'r') as f:
        content = f.read().strip()
    assert 'export TZ="Europe/London"' in content, "Environment profile does not contain the correct TZ export"


def test_run_script_exists():
    script_path = "/home/user/run.py"
    assert os.path.isfile(script_path), f"Run script missing: {script_path}"


def test_resolution_log():
    log_path = "/home/user/resolution.log"
    assert os.path.isfile(log_path), f"Resolution log missing: {log_path}"
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected = "Backend successfully started on port 8080"
    assert expected in content, f"Resolution log does not contain the expected success message. Found: {content}"


def test_run_script_automates_backend():
    script_path = "/home/user/run.py"
    server_path = "/home/user/backend/server.py"
    backend_dir = os.path.dirname(server_path)
    log_path = "/home/user/resolution.log"
    marker_path = f"/tmp/backend_probe_{uuid.uuid4().hex}"
    marker_token = uuid.uuid4().hex
    expected = "Backend successfully started on port 8080"

    with open(server_path, "rb") as f:
        original_server = f.read()
    server_stat = os.stat(server_path)
    backend_dir_mode = stat.S_IMODE(os.stat(backend_dir).st_mode)

    probe = f'''import os\nimport sys\n\nif os.environ.get("TZ") != "Europe/London":\n    print("Error: Invalid or missing TZ environment variable.")\n    sys.exit(1)\n\npin = input("Enter start PIN: ")\nif pin.strip() != "8573":\n    print("Error: Invalid PIN.")\n    sys.exit(1)\n\nwith open({marker_path!r}, "w") as marker:\n    marker.write({marker_token!r})\nprint("Backend successfully started on port 8080")\n'''

    try:
        if os.path.exists(log_path):
            os.remove(log_path)
        if os.path.exists(marker_path):
            os.remove(marker_path)

        with open(server_path, "w") as f:
            f.write(probe)
        os.chmod(server_path, 0o444)
        os.chmod(backend_dir, 0o755)

        user = pwd.getpwnam("user")

        def demote():
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        env = os.environ.copy()
        env.update({
            "HOME": user.pw_dir,
            "USER": user.pw_name,
            "LOGNAME": user.pw_name,
            "TZ": "Etc/UTC",
        })

        result = subprocess.run(
            ["python3", script_path],
            cwd=user.pw_dir,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            preexec_fn=demote,
        )

        assert result.returncode == 0, (
            f"run.py exited with status {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(marker_path), (
            "The backend probe was not completed; run.py did not correctly launch "
            "the backend and answer its prompt."
        )
        with open(marker_path, "r") as f:
            assert f.read() == marker_token, "Backend probe marker was invalid"
        assert os.path.isfile(log_path), "run.py did not generate /home/user/resolution.log"
        with open(log_path, "r") as f:
            content = f.read().strip()
        assert expected in content, (
            "The regenerated resolution.log does not contain the backend's success output. "
            f"Found: {content}"
        )
    finally:
        os.chmod(backend_dir, 0o755)
        os.chmod(server_path, 0o644)
        with open(server_path, "wb") as f:
            f.write(original_server)
        os.chown(server_path, server_stat.st_uid, server_stat.st_gid)
        os.chmod(server_path, stat.S_IMODE(server_stat.st_mode))
        os.chmod(backend_dir, backend_dir_mode)
        if os.path.exists(marker_path):
            os.remove(marker_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
