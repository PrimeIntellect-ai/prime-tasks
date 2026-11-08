#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import pytest

OLD_CONFIGS = {
    "web.conf": b"# Web Config\nDEBUG_LEVEL=1\nSERVER_PORT=8080\nWORKERS=4\n",
    "db.conf": b"# DB Config\nDEBUG_LEVEL=0\nSERVER_PORT=5432\nMAX_CONN=100\n",
    "cache.conf": b"# Cache Config\nDEBUG_LEVEL=0\nSERVER_PORT=6379\nMEMORY=2G\n",
    "app.conf": b"# App Config\nDEBUG_LEVEL=1\nSERVER_PORT=8080\nMODULES=auth,payment\n",
}

INITIAL_CURRENT = {
    "db.conf": b"# DB Config\nDEBUG_LEVEL=0\nSERVER_PORT=5432\nMAX_CONN=100\n",
    "cache.conf": b"# Cache Config\nDEBUG_LEVEL=0\nSERVER_PORT=6379\nMEMORY=2G\n",
    "web.conf": b"# Web Config\nDEBUG_LEVEL=1\nSERVER_PORT=8080\nWORKERS=8\n",
    "app.conf": b"# App Config\nDEBUG_LEVEL=1\nSERVER_PORT=8080\nMODULES=auth,payment,shipping\n",
}


def expected_state():
    changed = sorted(
        name for name, content in INITIAL_CURRENT.items()
        if OLD_CONFIGS.get(name) != content
    )
    expected_current = dict(INITIAL_CURRENT)
    for name in changed:
        expected_current[name] = (
            expected_current[name]
            .replace(b"DEBUG_LEVEL=1", b"LOG_LEVEL=debug")
            .replace(b"SERVER_PORT=8080", b"SERVER_PORT=9000")
        )
    return changed, expected_current


def test_patch_log_contents():
    log_path = "/home/user/patch_log.txt"
    assert os.path.isfile(log_path), f"Missing patch log file at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["app.conf", "web.conf"]
    assert lines == expected_lines, f"Expected {log_path} to contain {expected_lines}, but got {lines}"


def test_patch_archive_contents():
    archive_path = "/home/user/configs_patch.tar.bz2"
    assert os.path.isfile(archive_path), f"Missing patch archive at {archive_path}"

    try:
        with tarfile.open(archive_path, "r:bz2") as tar:
            members = tar.getnames()
    except tarfile.TarError as e:
        pytest.fail(f"Failed to read {archive_path} as a bzip2 tarball: {e}")

    expected_members = {"app.conf", "web.conf"}
    assert set(members) == expected_members, f"Archive {archive_path} should contain exactly {expected_members}, but contains {members}"


def test_modified_files():
    current_configs_dir = "/home/user/configs_current"

    web_conf_path = os.path.join(current_configs_dir, "web.conf")
    assert os.path.isfile(web_conf_path), f"Missing {web_conf_path}"
    with open(web_conf_path, "r") as f:
        web_content = f.read()
    assert "LOG_LEVEL=debug" in web_content, "web.conf missing LOG_LEVEL=debug replacement"
    assert "SERVER_PORT=9000" in web_content, "web.conf missing SERVER_PORT=9000 replacement"
    assert "DEBUG_LEVEL=1" not in web_content, "web.conf still contains DEBUG_LEVEL=1"
    assert "SERVER_PORT=8080" not in web_content, "web.conf still contains SERVER_PORT=8080"
    assert "WORKERS=8" in web_content, "web.conf missing WORKERS=8"

    app_conf_path = os.path.join(current_configs_dir, "app.conf")
    assert os.path.isfile(app_conf_path), f"Missing {app_conf_path}"
    with open(app_conf_path, "r") as f:
        app_content = f.read()
    assert "LOG_LEVEL=debug" in app_content, "app.conf missing LOG_LEVEL=debug replacement"
    assert "SERVER_PORT=9000" in app_content, "app.conf missing SERVER_PORT=9000 replacement"
    assert "DEBUG_LEVEL=1" not in app_content, "app.conf still contains DEBUG_LEVEL=1"
    assert "SERVER_PORT=8080" not in app_content, "app.conf still contains SERVER_PORT=8080"
    assert "MODULES=auth,payment,shipping" in app_content, "app.conf missing MODULES=auth,payment,shipping"


def test_unmodified_files():
    current_configs_dir = "/home/user/configs_current"

    db_conf_path = os.path.join(current_configs_dir, "db.conf")
    assert os.path.isfile(db_conf_path), f"Missing {db_conf_path}"
    with open(db_conf_path, "r") as f:
        db_content = f.read()
    assert "DEBUG_LEVEL=0" in db_content, "db.conf should not be modified"
    assert "SERVER_PORT=5432" in db_content, "db.conf should not be modified"

    cache_conf_path = os.path.join(current_configs_dir, "cache.conf")
    assert os.path.isfile(cache_conf_path), f"Missing {cache_conf_path}"
    with open(cache_conf_path, "r") as f:
        cache_content = f.read()
    assert "DEBUG_LEVEL=0" in cache_content, "cache.conf should not be modified"
    assert "SERVER_PORT=6379" in cache_content, "cache.conf should not be modified"


def test_old_archive_is_intact():
    archive_path = "/home/user/configs_old.tar.gz"
    assert os.path.isfile(archive_path), f"Missing old archive at {archive_path}"
    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            members = tar.getmembers()
            assert len(members) == len(OLD_CONFIGS)
            assert {m.name for m in members} == set(OLD_CONFIGS)
            for member in members:
                assert member.isfile(), f"Old archive member {member.name} is not a regular file"
                extracted = tar.extractfile(member)
                assert extracted is not None
                assert extracted.read() == OLD_CONFIGS[member.name], f"Old archive member {member.name} was modified"
    except tarfile.TarError as e:
        pytest.fail(f"Failed to read {archive_path}: {e}")


def test_exact_differential_result_and_archive_payloads():
    changed, expected_current = expected_state()
    assert changed == ["app.conf", "web.conf"]

    current_dir = "/home/user/configs_current"
    assert set(os.listdir(current_dir)) == set(expected_current), "Current configuration directory has missing or extra entries"
    for name, expected_content in expected_current.items():
        path = os.path.join(current_dir, name)
        assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular file"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"{name} does not exactly match the required final configuration"

    log_path = "/home/user/patch_log.txt"
    with open(log_path, "rb") as f:
        assert f.read() == b"app.conf\nweb.conf\n", "Patch log must contain exactly the sorted changed basenames"

    archive_path = "/home/user/configs_patch.tar.bz2"
    assert not os.path.islink(archive_path), "Patch archive must be a regular file, not a symlink"
    try:
        with tarfile.open(archive_path, "r:bz2") as tar:
            members = tar.getmembers()
            assert [m.name for m in members] == changed, "Archive must contain each changed basename exactly once in sorted root-level order"
            for member in members:
                assert member.isfile(), f"Archive member {member.name} is not a regular file"
                assert "/" not in member.name and member.name not in (".", "..")
                extracted = tar.extractfile(member)
                assert extracted is not None
                payload = extracted.read()
                assert payload == expected_current[member.name], f"Archived payload for {member.name} is not the updated configuration"
                with open(os.path.join(current_dir, member.name), "rb") as f:
                    assert payload == f.read(), f"Archived {member.name} differs from the current updated file"
    except tarfile.TarError as e:
        pytest.fail(f"Failed to validate {archive_path}: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
