#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import stat
import subprocess
import tempfile
import uuid


def run_check(executable):
    marker = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as td:
        banned_path = os.path.join(td, marker + "-banned.txt")
        active_path = os.path.join(td, marker + "-active.txt")
        with open(banned_path, "w") as f:
            f.write(f"Token: {marker}\nUsername: bad\nRole: guest\nStatus: BANNED\n")
        with open(active_path, "w") as f:
            f.write(f"Token: {marker}\nUsername: good\nRole: dev\nStatus: ACTIVE\n")

        result_banned = subprocess.run([executable, banned_path], capture_output=True, text=True)
        assert result_banned.returncode == 1, "check_ban did not exit with status 1 for a BANNED profile."
        assert "Banned user detected" in result_banned.stdout, "check_ban did not print the expected message for a BANNED profile."

        result_active = subprocess.run([executable, active_path], capture_output=True, text=True)
        assert result_active.returncode == 0, "check_ban did not exit with status 0 for an ACTIVE profile."

        no_args = subprocess.run([executable], capture_output=True, text=True)
        assert no_args.returncode != 0, "check_ban must reject zero command-line arguments."

        two_args = subprocess.run([executable, active_path, banned_path], capture_output=True, text=True)
        assert two_args.returncode != 0, "check_ban must reject more than one command-line argument."


def test_check_ban_c_exists_and_compiles():
    source = "/home/user/check_ban.c"
    assert os.path.isfile(source), "/home/user/check_ban.c does not exist."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "check_ban_rebuilt")
        result = subprocess.run(["gcc", source, "-o", rebuilt], capture_output=True, text=True)
        assert result.returncode == 0, f"check_ban.c does not compile: {result.stderr}"
        run_check(rebuilt)


def test_check_ban_executable_behavior():
    executable = "/home/user/check_ban"
    assert os.path.isfile(executable), f"{executable} does not exist."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "check_ban is not a compiled executable."
    run_check(executable)


def test_build_profiles_expect_executes_tool_and_generates_profiles():
    expect_script = "/home/user/build_profiles.exp"
    tool = "/home/user/tools/create_profile.sh"
    profiles = "/home/user/profiles"
    assert os.path.isfile(expect_script), "/home/user/build_profiles.exp does not exist."

    with open(tool, "rb") as f:
        original_tool = f.read()
    original_mode = stat.S_IMODE(os.stat(tool).st_mode)
    invocation_log = os.path.join("/tmp", "profile-invocations-" + uuid.uuid4().hex)
    quoted_log = shlex.quote(invocation_log)
    instrumented = f'''#!/bin/bash
read -p "Enter Username: " u
read -p "Enter Role: " r
read -p "Enter Status: " s
printf '%s\\t%s\\t%s\\n' "$u" "$r" "$s" >> {quoted_log}
printf 'Username: %s\\nRole: %s\\nStatus: %s\\n' "$u" "$r" "$s" > "/home/user/profiles/$u.txt"
echo "Profile $u.txt created."
'''

    try:
        with open(tool, "w") as f:
            f.write(instrumented)
        os.chmod(tool, 0o755)
        for username in ("admin1", "user1", "baduser"):
            path = os.path.join(profiles, username + ".txt")
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(["expect", expect_script], cwd="/home/user", capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"build_profiles.exp failed when executed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(invocation_log), "build_profiles.exp did not invoke create_profile.sh."
        with open(invocation_log) as f:
            invocations = [line.rstrip("\n").split("\t") for line in f]
        assert invocations == [
            ["admin1", "sysadmin", "ACTIVE"],
            ["user1", "developer", "ACTIVE"],
            ["baduser", "guest", "BANNED"],
        ], "build_profiles.exp did not supply the required interactive responses."
    finally:
        with open(tool, "wb") as f:
            f.write(original_tool)
        os.chmod(tool, original_mode)
        if os.path.exists(invocation_log):
            os.remove(invocation_log)

    expected = {
        "admin1.txt": "Username: admin1\nRole: sysadmin\nStatus: ACTIVE\n",
        "user1.txt": "Username: user1\nRole: developer\nStatus: ACTIVE\n",
        "baduser.txt": "Username: baduser\nRole: guest\nStatus: BANNED\n",
    }
    for filename, contents in expected.items():
        path = os.path.join(profiles, filename)
        assert os.path.isfile(path), f"{filename} was not generated in {profiles}."
        with open(path) as f:
            assert f.read() == contents, f"{filename} has incorrect profile contents."


def test_git_repo_and_hook():
    git_dir = "/home/user/profiles/.git"
    assert os.path.isdir(git_dir), "Git repository was not initialized in /home/user/profiles/."

    hook_path = os.path.join(git_dir, "hooks", "pre-commit")
    assert os.path.isfile(hook_path), f"pre-commit hook does not exist at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"pre-commit hook at {hook_path} is not executable."


def test_hook_staged_file_behavior():
    source_hook = "/home/user/profiles/.git/hooks/pre-commit"
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as repo:
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        hook = os.path.join(repo, ".git", "hooks", "pre-commit")
        shutil.copy2(source_hook, hook)
        os.chmod(hook, os.stat(hook).st_mode | stat.S_IXUSR)

        active_name = f"active-{token}.txt"
        ignored_name = f"banned-{token}.dat"
        with open(os.path.join(repo, active_name), "w") as f:
            f.write(f"Username: {token}\nStatus: ACTIVE\n")
        with open(os.path.join(repo, ignored_name), "w") as f:
            f.write("Status: BANNED\n")
        subprocess.run(["git", "add", active_name, ignored_name], cwd=repo, check=True)
        allowed = subprocess.run([hook], cwd=repo, capture_output=True, text=True)
        assert allowed.returncode == 0, "pre-commit hook rejected staged safe .txt files or inspected non-.txt files."

        subprocess.run(["git", "reset", "-q"], cwd=repo, check=True)
        banned_name = f"profile-{uuid.uuid4().hex}.txt"
        with open(os.path.join(repo, banned_name), "w") as f:
            f.write(f"Username: {token}\nRole: guest\nStatus: BANNED\n")
        subprocess.run(["git", "add", banned_name], cwd=repo, check=True)
        rejected = subprocess.run([hook], cwd=repo, capture_output=True, text=True)
        assert rejected.returncode == 1, "pre-commit hook did not reject a staged BANNED .txt profile."


def test_git_commit_status():
    repo_dir = "/home/user/profiles"

    for user in ["admin1", "user1", "baduser"]:
        assert os.path.isfile(os.path.join(repo_dir, f"{user}.txt")), f"{user}.txt was not generated in {repo_dir}."

    result_ls = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=repo_dir, capture_output=True, text=True)
    assert result_ls.returncode == 0, "Failed to get git ls-tree. Is there a commit?"
    committed_files = result_ls.stdout.strip().split("\n")
    assert "admin1.txt" in committed_files, "admin1.txt is not committed."
    assert "user1.txt" in committed_files, "user1.txt is not committed."
    assert "baduser.txt" not in committed_files, "baduser.txt should not be committed."

    subject = subprocess.run(["git", "log", "-1", "--format=%s"], cwd=repo_dir, capture_output=True, text=True)
    assert subject.returncode == 0
    assert subject.stdout.strip() == "Initial profiles", "The latest commit message is not exactly 'Initial profiles'."

    staged = subprocess.run(["git", "diff", "--cached", "--name-only"], cwd=repo_dir, capture_output=True, text=True)
    assert staged.returncode == 0
    assert "baduser.txt" not in staged.stdout.splitlines(), "baduser.txt remains staged."


def test_success_log():
    log_path = "/home/user/success_log.txt"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "Initial profiles", f"success_log.txt contains '{content}' instead of 'Initial profiles'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
