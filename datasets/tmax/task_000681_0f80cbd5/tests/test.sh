#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import pytest


def test_nginx_config_fixed():
    nginx_conf = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Nginx configuration file {nginx_conf} does not exist."
    with open(nginx_conf, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8000;" in content, (
        "Nginx configuration was not updated correctly. "
        "Expected 'proxy_pass http://127.0.0.1:8000;' to be present."
    )


def test_symlink_created():
    symlink_path = "/home/user/app/data"
    expected_target = "/home/user/source_data"

    assert os.path.islink(symlink_path), f"Path {symlink_path} is not a symlink. The deployment script failed to create it."

    actual_target = os.readlink(symlink_path)
    assert actual_target == expected_target, (
        f"Symlink {symlink_path} points to {actual_target}, "
        f"but expected it to point to {expected_target}."
    )


def test_verification_log():
    log_file = "/home/user/verification.log"
    assert os.path.isfile(log_file), f"Verification log file {log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read().strip()

    expected_content = "production_secret_data_7741"
    assert content == expected_content, (
        f"Verification log content is incorrect. "
        f"Expected '{expected_content}', got '{content}'."
    )


def test_deploy_script_exists():
    deploy_script = "/home/user/deploy.py"
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} does not exist."


def test_live_endpoint():
    url = "http://127.0.0.1:8080/data"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            content = response.read().decode("utf-8").strip()

        expected_content = "production_secret_data_7741"
        assert content == expected_content, (
            f"Live endpoint returned incorrect data. "
            f"Expected '{expected_content}', got '{content}'."
        )
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx or application via {url}. Error: {e}")


def test_deploy_script_performs_deployment_actions(tmp_path):
    deploy_script = Path("/home/user/deploy.py")
    fstab = Path("/home/user/fstab_config")
    requirements = Path("/home/user/app/requirements.txt")
    assert deploy_script.is_file(), f"Deployment script {deploy_script} does not exist."

    original_fstab = fstab.read_bytes()
    original_requirements = requirements.read_bytes()
    token = uuid.uuid4().hex
    source = tmp_path / f"source_{token}"
    destination = tmp_path / "nested" / f"destination_{token}"
    source.mkdir()
    (source / "generated.txt").write_text(token)

    module_name = f"deploy_probe_{token}"
    package_dir = tmp_path / "probe_package"
    package_dir.mkdir()
    (package_dir / f"{module_name}.py").write_text(f"TOKEN = {token!r}\n")
    (package_dir / "setup.py").write_text(
        "from setuptools import setup\n"
        f"setup(name={module_name!r}, version='0.0.1', py_modules=[{module_name!r}])\n"
    )

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    gunicorn_log = tmp_path / "gunicorn.log"
    gunicorn_pids = tmp_path / "gunicorn.pids"
    gunicorn_wrapper = bin_dir / "gunicorn"
    gunicorn_wrapper.write_text(
        "#!/bin/sh\n"
        "printf '%s\\t%s\\n' \"$PWD\" \"$*\" >> \"$DEPLOY_GUNICORN_LOG\"\n"
        "echo $$ >> \"$DEPLOY_GUNICORN_PIDS\"\n"
        "sleep 30\n"
    )
    gunicorn_wrapper.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    env["DEPLOY_GUNICORN_LOG"] = str(gunicorn_log)
    env["DEPLOY_GUNICORN_PIDS"] = str(gunicorn_pids)
    env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"

    try:
        fstab.write_text(
            "# verifier-generated fstab entry\n"
            f"{source} {destination} none bind 0 0\n"
        )
        requirements.write_text(str(package_dir) + "\n")

        try:
            result = subprocess.run(
                ["python3", str(deploy_script)],
                cwd="/home/user",
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("deploy.py did not return after launching Gunicorn in the background")

        assert result.returncode == 0, f"deploy.py failed when executed: {result.stderr}"
        assert destination.is_symlink(), "deploy.py did not create a symlink for a generated bind entry"
        assert os.readlink(destination) == str(source), (
            f"Generated bind destination points to {os.readlink(destination)!r}, expected {str(source)!r}"
        )
        assert (destination / "generated.txt").read_text() == token

        imported = None
        deadline = time.time() + 5
        while time.time() < deadline:
            imported = subprocess.run(
                ["python3", "-c", f"import {module_name}; print({module_name}.TOKEN)"],
                cwd="/",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if imported.returncode == 0:
                break
            time.sleep(0.2)
        assert imported is not None and imported.returncode == 0, (
            "deploy.py did not install the dependency from /home/user/app/requirements.txt: "
            + (imported.stderr if imported else "")
        )
        assert imported.stdout.strip() == token

        deadline = time.time() + 3
        while time.time() < deadline and not gunicorn_log.exists():
            time.sleep(0.1)
        assert gunicorn_log.exists(), "deploy.py did not invoke gunicorn"
        launches = [line for line in gunicorn_log.read_text().splitlines() if line.strip()]
        assert launches, "deploy.py did not invoke gunicorn"
        cwd, args_text = launches[-1].split("\t", 1)
        args = shlex.split(args_text)
        assert cwd == "/home/user/app", f"Gunicorn was launched from {cwd}, not /home/user/app"
        assert "main:app" in args, "Gunicorn was not launched with main:app"
        assert "--bind" in args, "Gunicorn was not launched with --bind"
        bind_index = args.index("--bind")
        assert bind_index + 1 < len(args) and args[bind_index + 1] == "127.0.0.1:8000", (
            "Gunicorn was not bound to 127.0.0.1:8000"
        )
    finally:
        fstab.write_bytes(original_fstab)
        requirements.write_bytes(original_requirements)
        if gunicorn_pids.exists():
            for value in gunicorn_pids.read_text().splitlines():
                try:
                    os.kill(int(value), 9)
                except (ValueError, ProcessLookupError, PermissionError):
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
