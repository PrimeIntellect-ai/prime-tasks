#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

REPO_DIR = "/home/user/asset_processor"
BAD_COMMIT_FILE = "/home/user/bad_commit.txt"
PATCH_FILE = "/home/user/fix.patch"


def git(*args):
    return subprocess.check_output(
        ["git", "-C", REPO_DIR, *args], text=True
    ).strip()


def unique_commit(subject):
    commits = git("log", "--all", "--format=%H", f"--grep=^{subject}$").splitlines()
    assert len(commits) == 1, f"Could not uniquely derive commit '{subject}'."
    return commits[0]


def run_pipeline(checkout, dirname="test dir", filename="file with spaces.txt"):
    test_root = tempfile.mkdtemp(prefix="asset-verifier-")
    try:
        target_dir = os.path.join(test_root, dirname)
        os.makedirs(target_dir)
        test_file = os.path.join(target_dir, filename)
        with open(test_file, "w") as f:
            f.write("dummy content")

        script = os.path.join(checkout, "build_and_process.sh")
        result = subprocess.run(
            [script, target_dir],
            cwd=checkout,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result, test_file
    finally:
        shutil.rmtree(test_root, ignore_errors=True)


def test_bad_commit_identified():
    assert os.path.isfile(BAD_COMMIT_FILE), f"The file {BAD_COMMIT_FILE} does not exist."
    with open(BAD_COMMIT_FILE) as f:
        actual_hash = f.read().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", actual_hash), "bad_commit.txt must contain one full 40-character SHA-1 hash."
    expected_hash = unique_commit("Refactor loop")
    assert actual_hash == expected_hash, f"Incorrect bad commit identified. Expected '{expected_hash}', but got '{actual_hash}'."


def find_bisect_scripts():
    candidates = []
    excluded = {
        os.path.realpath(os.path.join(REPO_DIR, "build_and_process.sh")),
        os.path.realpath(BAD_COMMIT_FILE),
        os.path.realpath(PATCH_FILE),
    }
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            path = os.path.realpath(os.path.join(root, name))
            if path in excluded or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", errors="strict") as f:
                    content = f.read()
            except (OSError, UnicodeError):
                continue
            if re.search(r"(?:exit|return|sys\.exit\s*\()\s*125\b", content):
                candidates.append(path)
    return candidates


def run_bisect_script(script, checkout):
    if script.endswith(".py"):
        command = ["python3", script]
    elif os.access(script, os.X_OK):
        command = [script]
    else:
        command = ["bash", script]
    return subprocess.run(
        command,
        cwd=checkout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_automated_bisect_script_and_skip_handling():
    scripts = find_bisect_scripts()
    assert scripts, "No automated bisect test script with exit-code 125 skip handling was found."

    bad = unique_commit("Refactor loop")
    good = git("rev-parse", f"{bad}^")
    compile_error = unique_commit("Accidental compiler error")
    commits = [(good, 0), (bad, "bad"), (compile_error, 125)]

    worktree_root = tempfile.mkdtemp(prefix="bisect-worktrees-")
    try:
        failures = []
        for script in scripts:
            results = []
            usable = True
            for index, (commit, expected) in enumerate(commits):
                checkout = os.path.join(worktree_root, f"w{index}")
                subprocess.run(
                    ["git", "-C", REPO_DIR, "worktree", "add", "--detach", checkout, commit],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                try:
                    result = run_bisect_script(script, checkout)
                    results.append((result.returncode, result.stdout, result.stderr))
                finally:
                    subprocess.run(
                        ["git", "-C", REPO_DIR, "worktree", "remove", "--force", checkout],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )

            good_rc, bad_rc, skip_rc = [item[0] for item in results]
            if good_rc == 0 and bad_rc not in (0, 125) and skip_rc == 125:
                usable = True
            else:
                usable = False
                failures.append(f"{script}: return codes good/bad/unbuildable were {good_rc}/{bad_rc}/{skip_rc}")
            if usable:
                return

        assert False, "No bisect script correctly classified good, bad, and unbuildable commits. " + "; ".join(failures)
    finally:
        shutil.rmtree(worktree_root, ignore_errors=True)
        subprocess.run(
            ["git", "-C", REPO_DIR, "worktree", "prune"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )


def test_fix_patch_exists_and_applies_to_original_main():
    assert os.path.isfile(PATCH_FILE), f"The patch file {PATCH_FILE} does not exist."
    assert os.path.getsize(PATCH_FILE) > 0, f"The patch file {PATCH_FILE} is empty."
    with open(PATCH_FILE) as f:
        content = f.read()
    assert "diff" in content or "---" in content, f"The file {PATCH_FILE} does not appear to be a valid patch."

    original_main = unique_commit("Update processor 200")
    checkout = tempfile.mkdtemp(prefix="patch-check-")
    shutil.rmtree(checkout)
    try:
        subprocess.run(
            ["git", "-C", REPO_DIR, "worktree", "add", "--detach", checkout, original_main],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        applied = subprocess.run(
            ["git", "-C", checkout, "apply", "--check", PATCH_FILE],
            capture_output=True,
            text=True,
        )
        assert applied.returncode == 0, f"fix.patch does not apply to the original main branch:\n{applied.stderr}"
        subprocess.run(["git", "-C", checkout, "apply", PATCH_FILE], check=True)
        result, test_file = run_pipeline(checkout, "patched dir", "patched file with spaces.txt")
        assert result.returncode == 0, f"Patched script failed with return code {result.returncode}.\nStderr: {result.stderr}"
        assert f"Processed: {test_file}" in result.stdout, "Applying fix.patch does not fix processing of filenames with spaces."
    finally:
        if os.path.exists(checkout):
            subprocess.run(
                ["git", "-C", REPO_DIR, "worktree", "remove", "--force", checkout],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        subprocess.run(["git", "-C", REPO_DIR, "worktree", "prune"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_script_handles_spaces_correctly():
    script_path = os.path.join(REPO_DIR, "build_and_process.sh")
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    result, test_file = run_pipeline(REPO_DIR)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    expected_output = f"Processed: {test_file}"
    assert expected_output in result.stdout, (
        "The script did not correctly process the file with spaces.\n"
        f"Expected output to contain: '{expected_output}'\nActual output:\n{result.stdout}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
