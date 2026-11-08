#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid
import pytest

PASSWD_PATH = "/home/user/mock_passwd"
CONF_PATH = "/home/user/logrotate_updates.conf"
V1_TARGET = "/home/user/releases/v1/config.ini"
V2_TARGET = "/home/user/releases/v2/config.ini"

CANONICAL_PASSWD = (
    "alice:x:1000:1001:Alice:/home/user/mock_homes/alice:/bin/bash\n"
    "bob:x:1001:1001:Bob:/home/user/mock_homes/bob:/bin/bash\n"
    "charlie:x:1002:1002:Charlie:/home/user/mock_homes/charlie:/bin/bash\n"
)

CANONICAL_USERS = [
    {"username": "alice", "gid": "1001", "homedir": "/home/user/mock_homes/alice"},
    {"username": "bob", "gid": "1001", "homedir": "/home/user/mock_homes/bob"},
    {"username": "charlie", "gid": "1002", "homedir": "/home/user/mock_homes/charlie"},
]


def get_users_info():
    passwd_path = PASSWD_PATH
    assert os.path.isfile(passwd_path), f"{passwd_path} is missing"

    users = []
    with open(passwd_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) >= 6:
                users.append({
                    "username": parts[0],
                    "gid": parts[3],
                    "homedir": parts[5]
                })
    return users


def normalized_expected(users):
    expected_blocks = []
    for user in users:
        if user["gid"] == "1001":
            expected_blocks.append(
                f"{user['homedir']}/logs/*.log {{\n"
                "    daily\n"
                "    rotate 7\n"
                "    compress\n"
                "}"
            )
    expected_content = "\n".join(expected_blocks) + "\n"
    return "\n".join(line.rstrip() for line in expected_content.strip().splitlines())


def assert_state(users):
    for user in users:
        symlink_path = os.path.join(user["homedir"], "app_config")
        assert os.path.islink(symlink_path), f"Symlink {symlink_path} is missing or not a symlink"
        target = os.readlink(symlink_path)
        expected_target = V2_TARGET if user["gid"] == "1001" else V1_TARGET
        assert target == expected_target, (
            f"Symlink for {user['username']} should point to {expected_target}, but points to {target}"
        )

    assert os.path.isfile(CONF_PATH), f"{CONF_PATH} is missing"
    with open(CONF_PATH, "r") as f:
        actual_content = f.read()
    actual_normalized = "\n".join(line.rstrip() for line in actual_content.strip().splitlines())
    expected_normalized = normalized_expected(users)
    assert actual_normalized == expected_normalized, (
        f"Content of {CONF_PATH} does not match expected format.\n"
        f"Expected:\n{expected_normalized}\n\nActual:\n{actual_normalized}"
    )


def reset_links(users):
    for user in users:
        os.makedirs(os.path.join(user["homedir"], "logs"), exist_ok=True)
        link = os.path.join(user["homedir"], "app_config")
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink(V1_TARGET, link)


def test_mock_passwd_unchanged():
    assert os.path.isfile(PASSWD_PATH), f"{PASSWD_PATH} is missing"
    with open(PASSWD_PATH, "r") as f:
        assert f.read() == CANONICAL_PASSWD, f"{PASSWD_PATH} was modified"


def test_symlinks_updated():
    users = get_users_info()
    for user in users:
        symlink_path = os.path.join(user["homedir"], "app_config")
        assert os.path.islink(symlink_path), f"Symlink {symlink_path} is missing or not a symlink"

        target = os.readlink(symlink_path)
        if user["gid"] == "1001":
            assert target == V2_TARGET, f"Symlink for {user['username']} (GID 1001) should point to {V2_TARGET}, but points to {target}"
        else:
            assert target == V1_TARGET, f"Symlink for {user['username']} (GID != 1001) should point to {V1_TARGET}, but points to {target}"


def test_logrotate_updates_content():
    users = get_users_info()
    expected_blocks = []

    for user in users:
        if user["gid"] == "1001":
            block = (
                f"{user['homedir']}/logs/*.log {{\n"
                "    daily\n"
                "    rotate 7\n"
                "    compress\n"
                "}"
            )
            expected_blocks.append(block)

    expected_content = "\n".join(expected_blocks) + "\n"
    assert os.path.isfile(CONF_PATH), f"{CONF_PATH} is missing"

    with open(CONF_PATH, "r") as f:
        actual_content = f.read()

    expected_normalized = "\n".join(line.rstrip() for line in expected_content.strip().splitlines())
    actual_normalized = "\n".join(line.rstrip() for line in actual_content.strip().splitlines())

    assert actual_normalized == expected_normalized, (
        f"Content of {CONF_PATH} does not match expected format.\n"
        f"Expected:\n{expected_normalized}\n\nActual:\n{actual_normalized}"
    )


def test_program_exists_and_compiles():
    source = "/home/user/rollout.c"
    assert os.path.isfile(source) and not os.path.islink(source), f"{source} is missing or is not a regular file"
    result = subprocess.run(
        ["gcc", source, "-o", "/home/user/rollout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"rollout.c did not compile with GCC:\n{result.stderr}"
    assert os.path.isfile("/home/user/rollout") and os.access("/home/user/rollout", os.X_OK)


def test_compiled_program_reads_and_processes_passwd():
    token = uuid.uuid4().hex[:10]
    base = f"/home/user/verifier_homes_{token}"
    fixture_users = [
        {"username": f"target_{token}", "uid": "2100", "gid": "1001", "homedir": f"{base}/one"},
        {"username": f"other_{token}", "uid": "2101", "gid": "1002", "homedir": f"{base}/two"},
        {"username": f"second_{token}", "uid": "2102", "gid": "1001", "homedir": f"{base}/three"},
    ]
    fixture_passwd = "".join(
        f"{u['username']}:x:{u['uid']}:{u['gid']}:Verifier User:{u['homedir']}:/bin/bash\n"
        for u in fixture_users
    )

    cleanup_result = None
    try:
        reset_links(fixture_users)
        with open(PASSWD_PATH, "w") as f:
            f.write(fixture_passwd)
        if os.path.lexists(CONF_PATH):
            os.unlink(CONF_PATH)

        result = subprocess.run(
            ["/home/user/rollout"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Compiled rollout program failed:\n{result.stderr}"
        with open(PASSWD_PATH, "r") as f:
            assert f.read() == fixture_passwd, "The rollout program modified mock_passwd"
        assert_state(fixture_users)
    finally:
        with open(PASSWD_PATH, "w") as f:
            f.write(CANONICAL_PASSWD)
        reset_links(CANONICAL_USERS)
        if os.path.lexists(CONF_PATH):
            os.unlink(CONF_PATH)
        cleanup_result = subprocess.run(
            ["/home/user/rollout"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        shutil.rmtree(base, ignore_errors=True)

    assert cleanup_result.returncode == 0, f"Program failed on the required passwd data:\n{cleanup_result.stderr}"
    with open(PASSWD_PATH, "r") as f:
        assert f.read() == CANONICAL_PASSWD, "The rollout program modified mock_passwd"
    assert_state(CANONICAL_USERS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
