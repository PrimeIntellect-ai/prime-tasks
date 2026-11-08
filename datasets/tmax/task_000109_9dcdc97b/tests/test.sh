#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

SCRIPT = "/home/user/provision.py"
TENANTS = Path("/home/user/tenants")
LOG = Path("/home/user/provision_log.txt")


def run_script(username, env=None):
    return subprocess.run(
        ["python3", SCRIPT],
        input=username + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=15,
    )


def assert_tenant(username):
    root = TENANTS / username
    assert (root / "data").is_dir(), f"Directory {root / 'data'} was not created."
    assert (root / "logs").is_dir(), f"Directory {root / 'logs'} was not created."
    quota = root / ".quota"
    assert quota.is_file(), f"File {quota} was not created."
    content = quota.read_bytes()
    assert content in (b"10GB", b"10GB\n"), f"Unexpected contents in {quota}: {content!r}"


def test_provision_script_exists():
    assert os.path.isfile(SCRIPT), "/home/user/provision.py does not exist."


def test_provision_script_behavior_with_dynamic_usernames():
    usernames = [f"tenant_{secrets.token_hex(8)}" for _ in range(2)]
    before = LOG.read_bytes()

    for username in usernames:
        assert not (TENANTS / username).exists()
        process = run_script(username)
        assert process.returncode == 0, (
            f"Script exited with code {process.returncode}. Stderr: {process.stderr}"
        )
        assert process.stdout == "Enter username: Success\n", (
            f"Unexpected stdout or prompt ordering: {process.stdout!r}"
        )
        assert_tenant(username)

    expected_delta = b"".join(
        f"Provisioned {username}\n".encode() for username in usernames
    )
    after = LOG.read_bytes()
    assert after == before + expected_delta, (
        f"Log was not appended in the required exact format; delta was "
        f"{after[len(before):]!r}"
    )
    for username in usernames:
        assert f"Provisioned {username}\n".encode() in after


def test_insufficient_disk_space_branch():
    username = f"lowspace_{secrets.token_hex(8)}"
    tenant = TENANTS / username
    before_log = LOG.read_bytes()

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        marker = td_path / "disk_check_marker"
        sitecustomize = td_path / "sitecustomize.py"
        sitecustomize.write_text(r'''
import os
import shutil

_target = os.path.realpath("/home/user/tenants")
_marker = os.environ["DISK_CHECK_MARKER"]
_real_statvfs = os.statvfs
_real_disk_usage = shutil.disk_usage


def _is_target(path):
    try:
        return os.path.realpath(os.fspath(path)) == _target
    except (TypeError, ValueError):
        return False


def _mark():
    with open(_marker, "a") as f:
        f.write("checked\n")


def fake_statvfs(path):
    result = _real_statvfs(path)
    if not _is_target(path):
        return result
    _mark()
    values = list(result)
    values[3] = 0
    values[4] = 0
    return os.statvfs_result(values)


def fake_disk_usage(path):
    if not _is_target(path):
        return _real_disk_usage(path)
    _mark()
    result_type = type(_real_disk_usage("/"))
    total = 200 * 1024 * 1024
    return result_type(total, total, 0)


os.statvfs = fake_statvfs
shutil.disk_usage = fake_disk_usage
''')

        bindir = td_path / "bin"
        bindir.mkdir()
        fake_df = bindir / "df"
        fake_df.write_text(r'''#!/bin/sh
printf 'checked\n' >> "$DISK_CHECK_MARKER"
case " $* " in
  *" --output=avail "*|*" --output=available "*)
    printf 'Avail\n0\n'
    ;;
  *)
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
    printf 'fake 1024000 1024000 0 100%% /\n'
    ;;
esac
''')
        fake_df.chmod(0o755)

        env = os.environ.copy()
        env["PYTHONPATH"] = td + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
        env["DISK_CHECK_MARKER"] = str(marker)

        process = run_script(username, env=env)
        assert marker.is_file(), (
            "The script did not query free space for /home/user/tenants using a "
            "standard disk-space API."
        )

    assert process.returncode == 1, (
        f"Low-space run exited with code {process.returncode}; stderr: {process.stderr}"
    )
    assert process.stdout == "Enter username: Error: Insufficient disk space\n", (
        f"Unexpected low-space stdout or prompt ordering: {process.stdout!r}"
    )
    assert not tenant.exists(), "Tenant files were created despite insufficient space."
    assert LOG.read_bytes() == before_log, "Provision log changed despite insufficient space."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
