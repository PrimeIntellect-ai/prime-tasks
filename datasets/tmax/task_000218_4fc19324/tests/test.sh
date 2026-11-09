#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile

REPO_PATH = "/home/user/account_manager.git"
HOOK_PATH = "/home/user/account_manager.git/hooks/post-receive"
SCRIPT_PATH = "/home/user/apply_users.sh"


def expected_script(users):
    lines = ["#!/bin/bash"]
    for user in users:
        if user["action"] == "add":
            groups = user.get("groups", [])
            for group in groups:
                lines.append(f"groupadd -f {group}")
            if groups:
                lines.append(f"useradd -m -G {','.join(groups)} {user['username']}")
            else:
                lines.append(f"useradd -m {user['username']}")
        else:
            lines.append(f"userdel -r {user['username']}")
    return "\n".join(lines) + "\n"


def assert_generated_script(expected_content):
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} was not generated."
    perms = stat.S_IMODE(os.stat(SCRIPT_PATH).st_mode)
    assert perms == 0o700, (
        f"Script {SCRIPT_PATH} has incorrect permissions: {oct(perms)}, expected 0o700."
    )
    with open(SCRIPT_PATH, "r") as f:
        actual_content = f.read()
    assert actual_content == expected_content, (
        f"Script content is incorrect.\nExpected:\n{expected_content}\nActual:\n{actual_content}"
    )


def test_git_repo_exists_and_bare():
    assert os.path.isdir(REPO_PATH), f"Repository directory {REPO_PATH} does not exist."

    result = subprocess.run(
        ["git", "rev-parse", "--is-bare-repository"],
        cwd=REPO_PATH,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, "Git command failed in repository."
    assert result.stdout.strip() == "true", f"Repository at {REPO_PATH} is not a bare repository."


def test_post_receive_hook_exists_and_executable():
    assert os.path.isfile(HOOK_PATH), f"Hook file {HOOK_PATH} does not exist."
    st = os.stat(HOOK_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook file {HOOK_PATH} is not executable."


def test_hook_execution_and_output():
    if os.path.exists(SCRIPT_PATH):
        os.remove(SCRIPT_PATH)

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", REPO_PATH, tmpdir], check=True, capture_output=True)

        users_data = [
            {"username": "alice", "action": "add", "groups": ["wheel", "developers"]},
            {"username": "bob", "action": "remove"},
            {"username": "charlie", "action": "add", "groups": []},
        ]

        with open(os.path.join(tmpdir, "users.json"), "w") as f:
            json.dump(users_data, f)

        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "init.defaultBranch", "master"], cwd=tmpdir, check=False)
        subprocess.run(["git", "add", "users.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Add users"], cwd=tmpdir, check=True)
        push_result = subprocess.run(
            ["git", "push", "origin", "master"],
            cwd=tmpdir,
            capture_output=True,
            text=True,
        )
        assert push_result.returncode == 0, f"Git push failed:\n{push_result.stderr}"

    expected_content = """#!/bin/bash
groupadd -f wheel
groupadd -f developers
useradd -m -G wheel,developers alice
userdel -r bob
useradd -m charlie
"""
    assert_generated_script(expected_content)


def test_dynamic_payloads_and_newrev_are_used():
    token = secrets.token_hex(6)
    users_one = [
        {"username": f"removed_{token}", "action": "remove"},
        {"username": f"empty_{token}", "action": "add", "groups": []},
        {
            "username": f"multi_{token}",
            "action": "add",
            "groups": [f"third_{token}", f"first_{token}", f"second_{token}"],
        },
        {
            "username": f"single_{token}",
            "action": "add",
            "groups": [f"only_{token}"],
        },
    ]
    users_two = [
        {
            "username": f"later_{token}",
            "action": "add",
            "groups": [f"later_b_{token}", f"later_a_{token}"],
        },
        {"username": f"gone_{token}", "action": "remove"},
    ]

    branch_one = f"verify-one-{token}"
    branch_two = f"verify-two-{token}"

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", REPO_PATH, tmpdir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "dynamic@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.name", "Dynamic Test"], cwd=tmpdir, check=True)
        subprocess.run(["git", "checkout", "-b", branch_one], cwd=tmpdir, check=True, capture_output=True)

        users_file = os.path.join(tmpdir, "users.json")
        with open(users_file, "w") as f:
            json.dump(users_one, f)
        subprocess.run(["git", "add", "users.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Dynamic payload one"], cwd=tmpdir, check=True)
        first_rev = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=tmpdir, check=True, capture_output=True, text=True
        ).stdout.strip()
        push_one = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch_one}"],
            cwd=tmpdir,
            capture_output=True,
            text=True,
        )
        assert push_one.returncode == 0, f"First dynamic push failed:\n{push_one.stderr}"
        assert_generated_script(expected_script(users_one))

        with open(users_file, "w") as f:
            json.dump(users_two, f)
        subprocess.run(["git", "add", "users.json"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Dynamic payload two"], cwd=tmpdir, check=True)
        push_two = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch_two}"],
            cwd=tmpdir,
            capture_output=True,
            text=True,
        )
        assert push_two.returncode == 0, f"Second dynamic push failed:\n{push_two.stderr}"
        assert_generated_script(expected_script(users_two))

    # Invoke the executable hook with an older, non-tip commit to ensure it reads
    # newrev from stdin rather than using a fixed branch or the most recent ref.
    if os.path.exists(SCRIPT_PATH):
        os.remove(SCRIPT_PATH)
    hook_result = subprocess.run(
        [HOOK_PATH],
        cwd=REPO_PATH,
        input=f"{'0' * 40} {first_rev} refs/heads/replay-{token}\n",
        capture_output=True,
        text=True,
    )
    assert hook_result.returncode == 0, (
        f"Hook failed when supplied a valid newrev on stdin:\n{hook_result.stderr}"
    )
    assert_generated_script(expected_script(users_one))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
