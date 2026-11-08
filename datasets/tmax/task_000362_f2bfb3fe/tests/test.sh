#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess

ROTATOR_DIR = "/home/user/rotator"
MANIFEST_PATH = os.path.join(ROTATOR_DIR, "Cargo.toml")
USERS_PATH = "/home/user/server/users.json"
ACCESS_LOG_PATH = "/home/user/server/access.log"
ROTATED_JSON_PATH = "/home/user/server/users_rotated.json"
SHA256_PATH = "/home/user/server/users_rotated.json.sha256"

EXPECTED_JSON_CONTENT = (
    '[{"token":"tok_111","username":"alice"},'
    '{"token":"7d5ec9268ab731ba2073994ab69cc3a38f3224b1bf82098d752f9b871c530517","username":"bob"},'
    '{"token":"e40733d7d74dbedc1f1ec7de5e2b0ba52ecba2f9a7cd6cf0ddc7dcf6dd629de0","username":"charlie"},'
    '{"token":"tok_444","username":"david"}]'
)

EXPECTED_HASH = "0e4af7890f5a287236dc9da8a5ef8c85ebdaab3818eebfe396bc75ce08c37107"


def test_users_rotated_json_exists_and_content():
    assert os.path.isfile(ROTATED_JSON_PATH), f"File {ROTATED_JSON_PATH} does not exist."

    with open(ROTATED_JSON_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == EXPECTED_JSON_CONTENT, (
        f"Content of {ROTATED_JSON_PATH} does not match the expected minified JSON string. "
        "Ensure the objects are sorted by username and keys are sorted alphabetically."
    )


def test_users_rotated_json_permissions():
    assert os.path.isfile(ROTATED_JSON_PATH), f"File {ROTATED_JSON_PATH} does not exist."

    st = os.stat(ROTATED_JSON_PATH)
    perms = stat.S_IMODE(st.st_mode)

    assert perms == 0o600, f"Permissions for {ROTATED_JSON_PATH} are {oct(perms)}, expected 0o600."


def test_users_rotated_sha256_file_exists_and_content():
    assert os.path.isfile(SHA256_PATH), f"File {SHA256_PATH} does not exist."

    with open(SHA256_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == EXPECTED_HASH, (
        f"Content of {SHA256_PATH} is incorrect. Expected {EXPECTED_HASH}, got {content}."
    )


def test_users_rotated_actual_sha256():
    assert os.path.isfile(ROTATED_JSON_PATH), f"File {ROTATED_JSON_PATH} does not exist."

    with open(ROTATED_JSON_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    assert actual_hash == EXPECTED_HASH, (
        f"Actual SHA256 of {ROTATED_JSON_PATH} ({actual_hash}) does not match the expected hash ({EXPECTED_HASH})."
    )


def _snapshot(path):
    if not os.path.lexists(path):
        return None
    st = os.stat(path)
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid


def _restore(path, snapshot):
    if os.path.lexists(path):
        os.unlink(path)
    if snapshot is not None:
        data, mode, uid, gid = snapshot
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, mode)
        os.chown(path, uid, gid)


def test_rust_project_executes_and_handles_derived_inputs():
    assert os.path.isdir(ROTATOR_DIR), f"Rust project directory {ROTATOR_DIR} does not exist."
    assert os.path.isfile(MANIFEST_PATH), f"Cargo manifest {MANIFEST_PATH} does not exist."
    manifest_stat = os.lstat(MANIFEST_PATH)
    assert stat.S_ISREG(manifest_stat.st_mode) and not os.path.islink(MANIFEST_PATH), (
        f"{MANIFEST_PATH} must be a regular Cargo manifest."
    )

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST_PATH],
        cwd=ROTATOR_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, (
        "The submitted Cargo project is invalid:\n" + metadata_result.stderr
    )
    metadata = json.loads(metadata_result.stdout)
    bin_sources = [
        target["src_path"]
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", [])
    ]
    assert bin_sources, "The Cargo project does not contain a Rust binary target."

    rotator_real = os.path.realpath(ROTATOR_DIR)
    valid_source = False
    for source in bin_sources:
        source_real = os.path.realpath(source)
        try:
            inside = os.path.commonpath([rotator_real, source_real]) == rotator_real
        except ValueError:
            inside = False
        if inside and os.path.isfile(source) and not os.path.islink(source):
            valid_source = True
            break
    assert valid_source, "The Rust binary source must be a regular .rs file inside /home/user/rotator."

    suffix = secrets.token_hex(8)
    users = [
        {"username": f"safe_internal_{suffix}", "token": f"int_{suffix}"},
        {"username": f"leaked_http_{suffix}", "token": f"evil_{suffix}"},
        {"username": f"safe_local_{suffix}", "token": f"local_{suffix}"},
        {"username": f"leaked_https_{suffix}", "token": f"hack_{suffix}"},
        {"username": f"unseen_{suffix}", "token": f"quiet_{suffix}"},
    ]
    access_log = "\n".join([
        f"[2026-01-01T00:00:00Z] GET /login?redirect=http://internal.corp/dashboard&token=int_{suffix} HTTP/1.1 302",
        f"[2026-01-01T00:01:00Z] GET /login?redirect=http://evil.example/steal&token=evil_{suffix} HTTP/1.1 302",
        f"[2026-01-01T00:02:00Z] GET /login?redirect=http://localhost:8080/home&token=local_{suffix} HTTP/1.1 302",
        f"[2026-01-01T00:03:00Z] GET /login?redirect=https://attacker.example/collect&token=hack_{suffix} HTTP/1.1 302",
    ]) + "\n"

    leaked = {f"leaked_http_{suffix}", f"leaked_https_{suffix}"}
    expected_users = []
    for user in sorted(users, key=lambda item: item["username"]):
        token = user["token"]
        if user["username"] in leaked:
            token = hashlib.sha256(("ROTATED_" + user["username"]).encode("utf-8")).hexdigest()
        expected_users.append({"token": token, "username": user["username"]})
    expected = json.dumps(expected_users, separators=(",", ":"), ensure_ascii=False)

    snapshots = {
        path: _snapshot(path)
        for path in (USERS_PATH, ACCESS_LOG_PATH, ROTATED_JSON_PATH, SHA256_PATH)
    }
    try:
        with open(USERS_PATH, "w", encoding="utf-8") as f:
            json.dump(users, f)
        with open(ACCESS_LOG_PATH, "w", encoding="utf-8") as f:
            f.write(access_log)
        if os.path.lexists(ROTATED_JSON_PATH):
            os.unlink(ROTATED_JSON_PATH)
        if os.path.lexists(SHA256_PATH):
            os.unlink(SHA256_PATH)

        run_result = subprocess.run(
            ["cargo", "run", "--quiet", "--manifest-path", MANIFEST_PATH],
            cwd=ROTATOR_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert run_result.returncode == 0, (
            "The Rust program failed when executed:\n" + run_result.stderr
        )
        assert os.path.isfile(ROTATED_JSON_PATH), (
            "The executed Rust program did not create users_rotated.json."
        )
        with open(ROTATED_JSON_PATH, "r", encoding="utf-8") as f:
            actual = f.read()
        assert actual == expected, (
            "The Rust program did not correctly analyze and rotate a verifier-derived input dataset."
        )
    finally:
        for path, snapshot in snapshots.items():
            _restore(path, snapshot)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
