#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest
import requests

APP = Path("/home/user/app")
OPERATOR = APP / "operator"
NGINX_CONF = APP / "nginx/nginx.conf"


def test_manifest_content():
    manifest = APP / "manifest.yaml"
    assert manifest.is_file(), f"Manifest {manifest} does not exist"
    expected = """routes:
  - path: /api/a
    port: 8081
  - path: /api/b
    port: 8082
"""
    assert manifest.read_text().strip() == expected.strip(), "manifest.yaml does not contain the required routes"


def test_generated_nginx_config():
    assert NGINX_CONF.is_file(), f"Nginx config {NGINX_CONF} does not exist"
    config = NGINX_CONF.read_text()

    for path, port in (("/api/a", 8081), ("/api/b", 8082)):
        pattern = (
            rf"location\s+(?:=\s+)?{re.escape(path)}(?:\s|\{{).*?"
            rf"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):{port}/?\s*;"
        )
        assert re.search(pattern, config, re.DOTALL), f"No correct proxy mapping for {path} to port {port}"

    result = subprocess.run(
        ["nginx", "-t", "-c", str(NGINX_CONF)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, f"Generated Nginx configuration is invalid:\n{result.stdout}"


def test_nginx_routing_api_a():
    url = "http://127.0.0.1:8080/api/a"
    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for {url}, got {response.status_code}"
    assert response.content == b"backend-a", f"{url} did not return the backend-a response"


def test_nginx_routing_api_b():
    url = "http://127.0.0.1:8080/api/b"
    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for {url}, got {response.status_code}"
    assert response.content == b"backend-b", f"{url} did not return the backend-b response"


def test_backup_directory_and_files():
    backup_dir = "/home/user/app/backups"
    assert os.path.isdir(backup_dir), f"Backup directory {backup_dir} does not exist."

    backup_files = glob.glob(os.path.join(backup_dir, "nginx.conf.bak.*"))
    assert len(backup_files) > 0, f"No backup files matching 'nginx.conf.bak.*' found in {backup_dir}."


def test_bash_profile_env_vars():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"Profile file {profile_path} does not exist."

    with open(profile_path, "r") as f:
        content = f.read()

    assert "MANIFEST_PATH=/home/user/app/manifest.yaml" in content, "MANIFEST_PATH not found in .bash_profile"
    assert "NGINX_CONF_PATH=/home/user/app/nginx/nginx.conf" in content, "NGINX_CONF_PATH not found in .bash_profile"
    assert "BACKUP_DIR=/home/user/app/backups" in content, "BACKUP_DIR not found in .bash_profile"


def test_rust_operator_uses_manifest_env_and_performs_backup(tmp_path):
    source = OPERATOR / "src/main.rs"
    cargo_toml = OPERATOR / "Cargo.toml"
    assert source.is_file(), f"Rust source {source} does not exist"
    assert cargo_toml.is_file(), f"Cargo manifest {cargo_toml} does not exist"

    token = secrets.token_hex(6)
    route_a = f"/verify-{token}/a"
    route_b = f"/verify-{token}/b"
    port_a = 21000 + secrets.randbelow(1000)
    port_b = 23000 + secrets.randbelow(1000)

    manifest = tmp_path / "manifest.yaml"
    conf = tmp_path / "nginx.conf"
    backups = tmp_path / "backups"
    fake_bin = tmp_path / "bin"
    nginx_log = tmp_path / "nginx.args"
    backups.mkdir()
    fake_bin.mkdir()

    manifest.write_text(
        f"routes:\n  - path: {route_a}\n    port: {port_a}\n"
        f"  - path: {route_b}\n    port: {port_b}\n"
    )
    old_contents = f"# pre-existing verifier config {token}\n".encode()
    conf.write_bytes(old_contents)

    fake_nginx = fake_bin / "nginx"
    fake_nginx.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$FAKE_NGINX_LOG"\nexit 0\n')
    fake_nginx.chmod(0o755)

    env = os.environ.copy()
    env.update({
        "MANIFEST_PATH": str(manifest),
        "NGINX_CONF_PATH": str(conf),
        "BACKUP_DIR": str(backups),
        "FAKE_NGINX_LOG": str(nginx_log),
        "PATH": f"{fake_bin}:{env.get('PATH', '')}",
    })

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=OPERATOR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust operator failed when executed:\n{result.stdout}"

    generated = conf.read_text()
    for path, port in ((route_a, port_a), (route_b, port_b)):
        pattern = (
            rf"location\s+(?:=\s+)?{re.escape(path)}(?:\s|\{{).*?"
            rf"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):{port}/?\s*;"
        )
        assert re.search(pattern, generated, re.DOTALL), f"Operator did not generate mapping {path} -> {port}"

    backup_files = list(backups.iterdir())
    assert len(backup_files) == 1, f"Expected one backup, found {[p.name for p in backup_files]}"
    backup = backup_files[0]
    assert re.fullmatch(r"nginx\.conf\.bak\.\d+", backup.name), f"Invalid backup filename: {backup.name}"
    assert backup.read_bytes() == old_contents, "Backup does not contain the pre-overwrite Nginx configuration"

    assert nginx_log.is_file(), "Operator did not invoke nginx to reload the generated configuration"
    args = nginx_log.read_text().splitlines()
    assert args == ["-c", str(conf), "-s", "reload"], f"Unexpected nginx reload arguments: {args}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
