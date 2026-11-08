#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tarfile


def normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def assert_exact_archive(tar_path, expected_contents):
    assert os.path.isfile(tar_path), f"Backup tarball missing: {tar_path}"
    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getmembers()
        payload_members = [m for m in members if not m.isdir()]
        normalized_names = [normalized_member_name(m.name) for m in payload_members]

        assert normalized_names == list(expected_contents), \
            f"Archive has incorrect member paths: {normalized_names}"

        for member, normalized_name in zip(payload_members, normalized_names):
            assert not member.name.startswith("/"), f"Archive member is absolute: {member.name}"
            assert ".." not in normalized_name.split("/"), f"Archive member traverses directories: {member.name}"
            assert member.isfile(), f"{member.name} in tarball is not a regular file (was it dereferenced?)"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not extract {member.name}"
            assert extracted.read() == expected_contents[normalized_name], \
                f"Incorrect content in backed up {normalized_name}"


def test_script_exists_and_executable():
    script_path = "/home/user/rebuild_env.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script is not executable: {script_path}"


def test_active_directory_state():
    active_dir = "/home/user/app_data/active"
    assert os.path.isdir(active_dir), f"Directory missing: {active_dir}"

    items = set(os.listdir(active_dir))
    expected_items = {"db.conf", "keys.json"}

    stale_items = items - expected_items
    assert not stale_items, f"Stale files/links not removed from active directory: {stale_items}"

    missing_items = expected_items - items
    assert not missing_items, f"Required files/links missing from active directory: {missing_items}"

    db_conf_path = os.path.join(active_dir, "db.conf")
    assert os.path.islink(db_conf_path), f"{db_conf_path} is not a symlink"
    db_target = os.readlink(db_conf_path)
    assert os.path.abspath(os.path.join(active_dir, db_target)) == "/home/user/app_data/versions/db_config_v2.conf", \
        f"db.conf points to incorrect target: {db_target}"

    keys_json_path = os.path.join(active_dir, "keys.json")
    assert os.path.islink(keys_json_path), f"{keys_json_path} is not a symlink"
    keys_target = os.readlink(keys_json_path)
    assert os.path.abspath(os.path.join(active_dir, keys_target)) == "/home/user/app_data/versions/api_keys_v3.json", \
        f"keys.json points to incorrect target: {keys_target}"


def test_rebuild_log():
    log_path = "/home/user/rebuild.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Linked db.conf to db_config_v2.conf",
        "Linked keys.json to api_keys_v3.json"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected log entry missing: '{expected}'"

    assert len(lines) == 2, f"Log file contains unexpected entries. Found {len(lines)} lines, expected 2."


def test_backup_tarball():
    tar_path = "/home/user/backup/app_backup.tar.gz"
    assert os.path.isfile(tar_path), f"Backup tarball missing: {tar_path}"

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getmembers()
        db_conf_member = None
        keys_json_member = None

        for m in members:
            if m.name.endswith("active/db.conf"):
                db_conf_member = m
            elif m.name.endswith("active/keys.json"):
                keys_json_member = m

        assert db_conf_member is not None, "active/db.conf not found in backup tarball"
        assert keys_json_member is not None, "active/keys.json not found in backup tarball"
        assert db_conf_member.isfile(), f"{db_conf_member.name} in tarball is not a regular file (was it dereferenced?)"
        assert keys_json_member.isfile(), f"{keys_json_member.name} in tarball is not a regular file (was it dereferenced?)"

        f = tar.extractfile(db_conf_member)
        assert f is not None, "Could not extract db.conf from tarball"
        content = f.read().decode("utf-8").strip()
        assert content == "port=5433", f"Incorrect content in backed up db.conf: {content}"

    assert_exact_archive(tar_path, {
        "active/db.conf": b"port=5433\n",
        "active/keys.json": b'{"key": "new"}\n',
    })


def test_script_on_changed_manifest_and_state():
    token = secrets.token_hex(8)
    script_path = "/home/user/rebuild_env.sh"
    manifest_path = "/home/user/manifest.conf"
    versions_dir = "/home/user/app_data/versions"
    active_dir = "/home/user/app_data/active"
    backup_dir = "/home/user/backup"
    tar_path = os.path.join(backup_dir, "app_backup.tar.gz")
    log_path = "/home/user/rebuild.log"

    link_names = [f"service-{token}.conf", f"secret-{token}.json"]
    target_names = [f"config-{token}.dat", f"keys-{token}.dat"]
    target_contents = [
        f"dynamic-port={secrets.randbelow(50000) + 10000}\n".encode(),
        f'{{"dynamic": "{secrets.token_hex(12)}"}}\n'.encode(),
    ]

    os.makedirs(versions_dir, exist_ok=True)
    os.makedirs(backup_dir, exist_ok=True)
    for target_name, content in zip(target_names, target_contents):
        with open(os.path.join(versions_dir, target_name), "wb") as f:
            f.write(content)

    with open(manifest_path, "w") as f:
        for link_name, target_name in zip(link_names, target_names):
            f.write(f"{link_name}={target_name}\n")

    shutil.rmtree(active_dir)
    os.makedirs(active_dir)
    os.symlink("/dev/null", os.path.join(active_dir, link_names[0]))
    with open(os.path.join(active_dir, link_names[1]), "w") as f:
        f.write("must be replaced by a symlink\n")
    os.symlink("/dev/null", os.path.join(active_dir, f"stale-{token}.link"))
    with open(os.path.join(active_dir, f"stale-{token}.txt"), "w") as f:
        f.write("stale\n")

    sentinel = f"preexisting-log-entry-{token}"
    with open(log_path, "w") as f:
        f.write(sentinel + "\n")
    if os.path.lexists(tar_path):
        os.remove(tar_path)

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"rebuild_env.sh failed on a changed manifest (exit {result.returncode}):\nstdout={result.stdout}\nstderr={result.stderr}"

    assert set(os.listdir(active_dir)) == set(link_names), \
        f"Dynamic run did not remove stale entries or create exactly the manifest entries: {os.listdir(active_dir)}"

    for link_name, target_name in zip(link_names, target_names):
        link_path = os.path.join(active_dir, link_name)
        expected_target = os.path.join(versions_dir, target_name)
        assert os.path.islink(link_path), f"Dynamic manifest entry is not a symlink: {link_path}"
        actual_target = os.path.abspath(os.path.join(active_dir, os.readlink(link_path)))
        assert actual_target == expected_target, \
            f"{link_name} points to {actual_target}, expected {expected_target}"

    with open(log_path, "r") as f:
        lines = [line.rstrip("\n") for line in f]
    expected_lines = [sentinel] + [
        f"Linked {link_name} to {target_name}"
        for link_name, target_name in zip(link_names, target_names)
    ]
    assert lines == expected_lines, f"Dynamic run produced incorrect appended log lines: {lines}"

    assert_exact_archive(tar_path, {
        f"active/{link_names[0]}": target_contents[0],
        f"active/{link_names[1]}": target_contents[1],
    })
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
