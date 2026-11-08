#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import secrets
import shutil
import subprocess
import tarfile
import pytest

SCRIPT = "/home/user/sync_configs.py"
BASE = "/home/user/base_config.tar.gz"
LIVE = "/home/user/live_config"
TRACKED = "/home/user/tracked_config.tar.gz"
HEADER = b"# TRACKED CHANGE\n"


def test_sync_configs_script_exists():
    script_path = "/home/user/sync_configs.py"
    assert os.path.isfile(script_path), f"The script {script_path} must exist."


def test_live_config_db_conf_modified():
    db_conf = "/home/user/live_config/db.conf"
    assert os.path.isfile(db_conf), f"{db_conf} must exist."
    with open(db_conf, "r") as f:
        content = f.read()
    expected = "# TRACKED CHANGE\nhost=192.168.1.100\n"
    assert content.strip() == expected.strip(), f"{db_conf} does not have the correct tracked changes."


def test_live_config_new_conf_modified():
    new_conf = "/home/user/live_config/new.conf"
    assert os.path.isfile(new_conf), f"{new_conf} must exist."
    with open(new_conf, "r") as f:
        content = f.read()
    expected = "# TRACKED CHANGE\nmode=fast\n"
    assert content.strip() == expected.strip(), f"{new_conf} does not have the correct tracked changes."


def test_live_config_app_conf_untouched():
    app_conf = "/home/user/live_config/app.conf"
    assert os.path.isfile(app_conf), f"{app_conf} must exist."
    with open(app_conf, "r") as f:
        content = f.read()
    assert content.strip() == "setting=1", f"{app_conf} should not have been modified."


def test_live_config_cache_conf_untouched():
    cache_conf = "/home/user/live_config/cache.conf"
    assert os.path.isfile(cache_conf), f"{cache_conf} must exist."
    with open(cache_conf, "r") as f:
        content = f.read()
    assert content.strip() == "enabled=true", f"{cache_conf} should not have been modified."


def test_tracked_config_archive_exists_and_valid():
    archive_path = "/home/user/tracked_config.tar.gz"
    assert os.path.isfile(archive_path), f"The archive {archive_path} must exist."
    assert tarfile.is_tarfile(archive_path), f"The file {archive_path} must be a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = [os.path.basename(m.name) for m in tar.getmembers() if m.isfile()]

        for expected_file in ["app.conf", "db.conf", "cache.conf", "new.conf"]:
            assert expected_file in names, f"{expected_file} must be in the new tracked archive."

        db_member = next((m for m in tar.getmembers() if os.path.basename(m.name) == "db.conf"), None)
        assert db_member is not None, "db.conf must be found in the archive."

        f = tar.extractfile(db_member)
        content = f.read().decode("utf-8")
        assert "# TRACKED CHANGE" in content, "The archived db.conf must contain the tracked change header."


def _write(path, data):
    with open(path, "wb") as f:
        f.write(data)


def _make_baseline(files):
    with tarfile.open(BASE, "w:gz") as tar:
        for name, data in files.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


def _run_script():
    return subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def test_z_script_handles_fresh_inputs_and_corrupt_archive():
    token = secrets.token_hex(16).encode("ascii")
    baseline = {
        "same.conf": b"same=" + token + b"\n",
        "changed.conf": b"value=old-" + token + b"\n",
        "notes.txt": b"baseline-" + token + b"\n",
    }
    live = {
        "same.conf": baseline["same.conf"],
        "changed.conf": b"value=new-" + token + b"\n",
        "fresh.conf": b"fresh=" + token + b"\n",
        "notes.txt": b"live-" + token + b"\n",
    }

    shutil.rmtree(LIVE, ignore_errors=True)
    os.makedirs(LIVE)
    for name, data in live.items():
        _write(os.path.join(LIVE, name), data)
    _make_baseline(baseline)
    if os.path.lexists(TRACKED):
        os.remove(TRACKED)

    result = _run_script()
    assert result.returncode == 0, (
        f"Script failed on a valid randomized fixture with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )

    expected = {
        "same.conf": live["same.conf"],
        "changed.conf": HEADER + live["changed.conf"],
        "fresh.conf": HEADER + live["fresh.conf"],
        "notes.txt": live["notes.txt"],
    }
    for name, data in expected.items():
        with open(os.path.join(LIVE, name), "rb") as f:
            assert f.read() == data, f"Incorrect resulting contents for {name}"

    assert os.path.isfile(TRACKED), "The script did not create tracked_config.tar.gz"
    with open(TRACKED, "rb") as f:
        assert f.read(2) == b"\x1f\x8b", "The output archive is not gzip-compressed"
    with tarfile.open(TRACKED, "r:gz") as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        by_name = {}
        for member in members:
            by_name.setdefault(os.path.basename(member.name), []).append(member)
        for name, data in expected.items():
            assert name in by_name, f"{name} is missing from the tracked archive"
            assert len(by_name[name]) == 1, f"The tracked archive contains duplicate entries for {name}"
            extracted = tar.extractfile(by_name[name][0])
            assert extracted is not None
            assert extracted.read() == data, f"Archived contents for {name} do not match the live file"

    shutil.rmtree(LIVE, ignore_errors=True)
    os.makedirs(LIVE)
    _write(os.path.join(LIVE, "probe.conf"), b"probe=" + token + b"\n")
    with open(BASE, "wb") as f:
        f.write(gzip.compress(b"not a tar archive: " + token))

    corrupt_result = _run_script()
    assert corrupt_result.returncode == 1, (
        "A gzip stream that is not a valid tar archive must make the script exit with status 1; "
        f"got {corrupt_result.returncode}. stderr: {corrupt_result.stderr.decode(errors='replace')}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
