#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
REPO = "/home/user/manifest-repo"
BINARY = "/home/user/operator"
SOURCE = "/home/user/operator.cpp"
SPOOL = "/home/user/mail_spool.txt"
ACTIVE = "/home/user/active_network.log"
MANIFEST = os.path.join(REPO, "network-manifest.conf")
HOOK = os.path.join(REPO, ".git/hooks/post-commit")
INITIAL_MANIFEST = b"default_route=10.0.0.1\n"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def test_git_repo_exists_and_is_nonbare():
    assert os.path.isdir(os.path.join(REPO, ".git")), (
        "Git repository was not initialized at /home/user/manifest-repo."
    )
    result = run(["git", "rev-parse", "--is-bare-repository"], cwd=REPO)
    assert result.stdout.strip() == "false", "The repository must be non-bare."


def test_git_hook_executable():
    assert os.path.isfile(HOOK), f"Hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), f"Hook at {HOOK} is not executable."


def test_manifest_and_commit_are_exact():
    with open(MANIFEST, "rb") as f:
        assert f.read() == INITIAL_MANIFEST, "network-manifest.conf does not have the exact required contents."

    try:
        output = subprocess.check_output(
            ["git", "log", "--oneline"], cwd=REPO, text=True, stderr=subprocess.STDOUT
        )
        assert "Add initial network manifest" in output, "The required commit message was not found in the git log."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git log in {REPO}: {e.output}")

    commits = run(["git", "rev-list", "--all"], cwd=REPO).stdout.splitlines()
    matching = []
    for commit in commits:
        subject = run(["git", "show", "-s", "--format=%s", commit], cwd=REPO).stdout.rstrip("\n")
        if subject == "Add initial network manifest":
            matching.append(commit)
    assert matching, 'No commit has the exact message "Add initial network manifest".'
    assert any(
        subprocess.run(
            ["git", "show", f"{commit}:network-manifest.conf"],
            cwd=REPO,
            capture_output=True,
        ).stdout == INITIAL_MANIFEST
        for commit in matching
    ), "The required commit did not contain the exact initial manifest."


def test_initial_hook_execution():
    assert os.path.isfile(SPOOL), f"{SPOOL} does not exist. Hook may not have run."
    with open(SPOOL, "r") as f:
        content = f.read()
    assert "ALERT: Invalid route 10.0.0.1 rejected" in content, f"Expected alert not found in {SPOOL}."


def exercise_operator(path):
    assert os.path.isfile(path), f"Operator binary not found at {path}"
    assert os.access(path, os.X_OK), f"Operator at {path} is not executable."

    random_route = f"198.51.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    with tempfile.TemporaryDirectory() as temp_dir:
        conf = os.path.join(temp_dir, "network-manifest.conf")

        # Preserve the original fixed valid-route assertion, while ensuring the
        # operator locates the relevant line rather than assuming it is first.
        with open(conf, "w") as f:
            f.write("ignored_setting=yes\n")
            f.write("default_route=192.168.1.254\n")
        for target in (ACTIVE, SPOOL):
            try:
                os.remove(target)
            except FileNotFoundError:
                pass
        result = subprocess.run([path], cwd=temp_dir, capture_output=True)
        assert result.returncode == 0, "Operator did not exit with status 0 for valid route."
        assert os.path.isfile(ACTIVE), f"{ACTIVE} was not created."
        with open(ACTIVE, "rb") as f:
            assert f.read() == b"ROUTE_ACCEPTED\n", f"Unexpected contents in {ACTIVE}."
        assert not os.path.exists(SPOOL), "A valid route must not be rejected."

        # Preserve the original fixed invalid-route assertion.
        with open(conf, "w") as f:
            f.write("default_route=8.8.8.8\n")
        for target in (ACTIVE, SPOOL):
            try:
                os.remove(target)
            except FileNotFoundError:
                pass
        result = subprocess.run([path], cwd=temp_dir, capture_output=True)
        assert result.returncode == 0, "Operator did not exit with status 0 for invalid route."
        assert result.stdout == b"" and result.stderr == b"", "Invalid routes must be silently rejected."
        assert os.path.isfile(SPOOL), f"{SPOOL} was not created."
        with open(SPOOL, "rb") as f:
            assert f.read() == b"ALERT: Invalid route 8.8.8.8 rejected\n"
        assert not os.path.exists(ACTIVE), "An invalid route must not activate networking."

        # Use an unpredictable value so fixed-output implementations cannot pass.
        with open(conf, "w") as f:
            f.write("comment=unrelated\n")
            f.write(f"default_route={random_route}\n")
        for target in (ACTIVE, SPOOL):
            try:
                os.remove(target)
            except FileNotFoundError:
                pass
        result = subprocess.run([path], cwd=temp_dir, capture_output=True)
        assert result.returncode == 0, "Operator did not exit with status 0 for a generated invalid route."
        assert result.stdout == b"" and result.stderr == b"", "Invalid routes must be silently rejected."
        with open(SPOOL, "rb") as f:
            expected = f"ALERT: Invalid route {random_route} rejected\n".encode()
            assert f.read() == expected, "The operator did not parse and report the generated route exactly."
        assert not os.path.exists(ACTIVE), "A generated invalid route must not be accepted."

        # Preserve the original missing-file exit-status assertion.
        os.remove(conf)
        result = subprocess.run([path], cwd=temp_dir, capture_output=True)
        assert result.returncode == 0, "Operator did not exit with status 0 when file is missing."


def test_cpp_source_compiles_and_both_artifacts_work():
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.isfile(BINARY), f"Operator binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Operator at {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The installed operator must be a compiled native executable."

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "operator-from-source")
        result = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", rebuilt], text=True, capture_output=True
        )
        assert result.returncode == 0, f"operator.cpp does not compile as C++: {result.stderr}"
        exercise_operator(rebuilt)

    exercise_operator(BINARY)


def git_commit(message, path):
    run(["git", "add", path], cwd=REPO)
    run(
        ["git", "-c", "user.name=Verifier", "-c", "user.email=verifier@local", "commit", "-m", message],
        cwd=REPO,
    )


def test_hook_really_invokes_operator_and_applies_generated_manifest():
    marker = os.path.join(HOME, f"hook-marker-{secrets.token_hex(8)}")
    sentinel_name = f".verifier-sentinel-{secrets.token_hex(8)}"
    sentinel = os.path.join(REPO, sentinel_name)
    backup = os.path.join(HOME, f"operator-backup-{secrets.token_hex(8)}")
    original_mode = stat.S_IMODE(os.stat(BINARY).st_mode)

    # Replace the operator briefly with a probe. A commit unrelated to the
    # manifest must still execute /home/user/operator from the repository cwd.
    os.replace(BINARY, backup)
    try:
        with open(BINARY, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s\\n' \"$PWD\" > {marker!r}\n")
            f.write("exit 0\n")
        os.chmod(BINARY, 0o755)
        with open(sentinel, "w") as f:
            f.write(secrets.token_hex(16) + "\n")
        git_commit("Verifier hook invocation probe", sentinel_name)
        assert os.path.isfile(marker), "The post-commit hook did not invoke /home/user/operator."
        with open(marker, "r") as f:
            assert f.read() == REPO + "\n", "The hook did not run the operator in the repository directory."
    finally:
        try:
            os.remove(BINARY)
        except FileNotFoundError:
            pass
        os.replace(backup, BINARY)
        os.chmod(BINARY, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    # Exercise the real hook/operator chain with an unpredictable route and an
    # empty spool, then restore the required final manifest contents.
    route = f"203.0.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    with open(MANIFEST, "w") as f:
        f.write(f"default_route={route}\n")
    try:
        os.remove(SPOOL)
    except FileNotFoundError:
        pass
    git_commit("Verifier generated route", "network-manifest.conf")
    with open(SPOOL, "rb") as f:
        expected = f"ALERT: Invalid route {route} rejected\n".encode()
        assert f.read() == expected, "The post-commit hook did not apply the generated manifest through the operator."

    with open(MANIFEST, "wb") as f:
        f.write(INITIAL_MANIFEST)
    git_commit("Restore initial network manifest", "network-manifest.conf")
    with open(MANIFEST, "rb") as f:
        assert f.read() == INITIAL_MANIFEST
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
