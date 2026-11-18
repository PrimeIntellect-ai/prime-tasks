#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import posixpath
import secrets
import subprocess
import tarfile

TRACKER = "/tmp/tracker_verify"


def test_extracted_configs_exist():
    base_dir = "/home/user/extracted_configs"
    assert os.path.isdir(base_dir), f"Directory {base_dir} does not exist."
    for conf in ["web.conf", "db.conf", "cache.conf"]:
        conf_path = os.path.join(base_dir, conf)
        assert os.path.isfile(conf_path), f"Extracted file {conf_path} is missing."


def load_manifest(manifest_path="/home/user/manifest.json"):
    assert os.path.isfile(manifest_path), f"{manifest_path} does not exist."
    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{manifest_path} is not valid JSON."
    assert isinstance(data, list), f"JSON in {manifest_path} must be an array."
    for item in data:
        assert isinstance(item, dict), "Every manifest entry must be an object."
        assert set(item) == {"link_name", "target_path", "sha256"}, \
            "Each manifest object must contain exactly link_name, target_path, and sha256."
    return data


def test_manifest_json():
    data = load_manifest()
    assert len(data) == 2, f"Expected exactly 2 objects in /home/user/manifest.json, found {len(data)}."

    entries = {item.get("link_name"): item for item in data}

    assert "active_web" in entries, "Missing 'active_web' in manifest."
    assert "active_db" in entries, "Missing 'active_db' in manifest."

    for link_name, conf_name in [("active_web", "web.conf"), ("active_db", "db.conf")]:
        target_path = f"/home/user/extracted_configs/{conf_name}"
        assert entries[link_name].get("target_path") == target_path, \
            f"Incorrect target_path for {link_name}."

        with open(target_path, "rb") as f:
            expected_sha256 = hashlib.sha256(f.read()).hexdigest()

        assert entries[link_name].get("sha256") == expected_sha256, \
            f"Incorrect sha256 for {link_name}."


def normalized_member_name(name):
    assert not name.startswith("/"), f"Archive contains absolute path: {name}"
    normalized = posixpath.normpath(name)
    assert normalized != ".." and not normalized.startswith("../"), \
        f"Archive contains an unsafe path: {name}"
    return normalized


def test_update_tar_gz():
    tar_path = "/home/user/update.tar.gz"
    assert os.path.isfile(tar_path), f"{tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive."

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()

        # Normalize paths by removing leading './' if present
        cleaned_names = [n.lstrip("./") for n in names]

        assert "manifest.json" in cleaned_names, "manifest.json is missing from the final archive."
        assert "extracted_configs/web.conf" in cleaned_names, "extracted_configs/web.conf is missing from the final archive."
        assert "extracted_configs/db.conf" in cleaned_names, "extracted_configs/db.conf is missing from the final archive."

        assert "extracted_configs/cache.conf" not in cleaned_names, "cache.conf should not be included in the final archive."
        assert "extracted_configs/missing.conf" not in cleaned_names, "missing.conf should not be included in the final archive."

        expected_files = {
            "manifest.json",
            "extracted_configs/web.conf",
            "extracted_configs/db.conf",
        }
        allowed_dirs = {".", "extracted_configs"}
        archived_files = {}

        for member in members:
            name = normalized_member_name(member.name)
            if member.isdir():
                assert name in allowed_dirs, f"Unexpected directory in archive: {member.name}"
                continue
            assert member.isfile(), f"Archive member must be a regular file: {member.name}"
            assert name in expected_files, f"Unexpected file in archive: {member.name}"
            assert name not in archived_files, f"Duplicate archive member: {name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_files[name] = extracted.read()

    assert set(archived_files) == expected_files, "Archive must contain exactly the required files."
    with open("/home/user/manifest.json", "rb") as f:
        assert archived_files["manifest.json"] == f.read(), \
            "Archived manifest.json differs from the generated manifest."
    for conf_name in ["web.conf", "db.conf"]:
        with open(f"/home/user/extracted_configs/{conf_name}", "rb") as f:
            assert archived_files[f"extracted_configs/{conf_name}"] == f.read(), \
                f"Archived {conf_name} differs from its resolved target."


def expected_valid_links():
    result = {}
    tree = "/home/user/config_tree"
    for name in os.listdir(tree):
        link_path = os.path.join(tree, name)
        if not os.path.islink(link_path):
            continue
        target = os.path.realpath(link_path)
        if not os.path.isfile(target):
            continue
        with open(target, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        result[name] = {
            "link_name": name,
            "target_path": target,
            "sha256": digest,
        }
    return result


def test_tracker_handles_unseen_links():
    token = secrets.token_hex(12)
    link_name = f"verify_{token}"
    broken_name = f"verify_broken_{token}"
    target = f"/home/user/extracted_configs/{token}.conf"
    content = secrets.token_bytes(97)

    with open(target, "wb") as f:
        f.write(content)
    os.symlink(target, f"/home/user/config_tree/{link_name}")
    os.symlink(f"/home/user/extracted_configs/missing_{token}.conf",
               f"/home/user/config_tree/{broken_name}")

    expected = expected_valid_links()
    subprocess.run([TRACKER], cwd="/home/user", check=True, timeout=15)
    data = load_manifest()

    assert len(data) == len(expected), "Tracker did not emit exactly all valid symlinks."
    entries = {item["link_name"]: item for item in data}
    assert len(entries) == len(data), "Manifest contains duplicate link names."
    assert entries == expected, "Tracker output is incorrect for dynamically added links."
    assert broken_name not in entries, "Tracker included a broken symlink."


def test_final_state():
    assert os.path.isfile("/home/user/tracker.c"), "/home/user/tracker.c does not exist."
    test_extracted_configs_exist()
    test_manifest_json()
    test_update_tar_gz()
    test_tracker_handles_unseen_links()
TEST_EOF

if gcc /home/user/tracker.c -o /tmp/tracker_verify -lcrypto \
   && timeout 15s bash -c 'cd /home/user && /tmp/tracker_verify' \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
