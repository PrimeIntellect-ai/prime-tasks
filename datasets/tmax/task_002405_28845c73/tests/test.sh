#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import json
import shutil
import tempfile

REPO_PATH = "/home/user/app_repo"
HOOK_PATH = os.path.join(REPO_PATH, ".git/hooks/pre-commit")


def test_test_results_log():
    log_path = "/home/user/test_results.log"

    # Do not trust a log left by the agent. Remove it and require the installed
    # hook to recreate it by running the real pipeline.
    if os.path.exists(log_path):
        os.remove(log_path)

    assert os.path.isfile(HOOK_PATH), f"Git hook {HOOK_PATH} does not exist."
    assert os.access(HOOK_PATH, os.X_OK), f"Git hook {HOOK_PATH} is not executable."

    result = subprocess.run(
        [HOOK_PATH],
        cwd=REPO_PATH,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        "The pre-commit hook did not successfully run the real pipeline. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )

    assert os.path.isfile(log_path), f"{log_path} does not exist. The pipeline may not have run successfully."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "PIPELINE_PASSED" in content, f"Expected 'PIPELINE_PASSED' in {log_path}, got: {content}"


def test_pre_commit_hook():
    hook_path = HOOK_PATH
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."

    quota_path = os.path.join(REPO_PATH, "check_quota.sh")
    tests_path = os.path.join(REPO_PATH, "run_tests.py")
    backup_dir = tempfile.mkdtemp(prefix="hook-test-")
    quota_backup = os.path.join(backup_dir, "check_quota.sh")
    tests_backup = os.path.join(backup_dir, "run_tests.py")
    trace_path = os.path.join(backup_dir, "trace")

    shutil.copy2(quota_path, quota_backup)
    shutil.copy2(tests_path, tests_backup)

    try:
        with open(quota_path, "w") as f:
            f.write("#!/bin/sh\nprintf 'quota\\n' >> \"$HOOK_TRACE\"\nexit \"${QUOTA_RC:-0}\"\n")
        os.chmod(quota_path, 0o755)

        with open(tests_path, "w") as f:
            f.write(
                "import os, sys\n"
                "with open(os.environ['HOOK_TRACE'], 'a') as trace:\n"
                "    trace.write('tests\\n')\n"
                "sys.exit(int(os.environ.get('TEST_RC', '0')))\n"
            )

        def run_hook(quota_rc, test_rc):
            if os.path.exists(trace_path):
                os.remove(trace_path)
            env = os.environ.copy()
            env["HOOK_TRACE"] = trace_path
            env["QUOTA_RC"] = str(quota_rc)
            env["TEST_RC"] = str(test_rc)
            result = subprocess.run(
                [hook_path],
                cwd=REPO_PATH,
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if os.path.exists(trace_path):
                with open(trace_path, "r") as f:
                    trace = f.read().splitlines()
            else:
                trace = []
            return result, trace

        # A quota failure must stop the hook before run_tests.py.
        result, trace = run_hook(1, 0)
        assert result.returncode != 0, "The hook must fail when ./check_quota.sh fails."
        assert trace == ["quota"], f"Quota failure must abort before tests; observed execution order: {trace}"

        # Tests must run after a successful quota check, and their failure must
        # make the hook fail.
        result, trace = run_hook(0, 1)
        assert result.returncode != 0, "The hook must fail when python3 run_tests.py fails."
        assert trace == ["quota", "tests"], f"Expected quota then tests; observed execution order: {trace}"

        # With both commands successful, the hook must succeed in the same order.
        result, trace = run_hook(0, 0)
        assert result.returncode == 0, "The hook must succeed when both required commands succeed."
        assert trace == ["quota", "tests"], f"Expected quota then tests; observed execution order: {trace}"
    finally:
        shutil.copy2(quota_backup, quota_path)
        shutil.copy2(tests_backup, tests_path)
        shutil.rmtree(backup_dir, ignore_errors=True)


def test_check_quota_sh():
    script_path = "/home/user/app_repo/check_quota.sh"
    db_path = "/home/user/app_repo/users.db"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    # Save original db content to restore later
    with open(db_path, "rb") as f:
        original_db = f.read()

    try:
        # Test with small db (<= 1024 bytes)
        with open(db_path, "wb") as f:
            f.write(b"0" * 500)

        res_ok = subprocess.run([script_path], cwd="/home/user/app_repo", capture_output=True, text=True)
        assert res_ok.returncode == 0, f"check_quota.sh should exit with 0 for files <= 1024 bytes, got {res_ok.returncode}"
        assert "QUOTA_OK" in res_ok.stdout, f"Expected 'QUOTA_OK' in stdout for small file, got {res_ok.stdout}"

        # Test with large db (> 1024 bytes)
        with open(db_path, "wb") as f:
            f.write(b"0" * 1025)

        res_exceeded = subprocess.run([script_path], cwd="/home/user/app_repo", capture_output=True, text=True)
        assert res_exceeded.returncode == 1, f"check_quota.sh should exit with 1 for files > 1024 bytes, got {res_exceeded.returncode}"
        assert "QUOTA_EXCEEDED" in res_exceeded.stdout, f"Expected 'QUOTA_EXCEEDED' in stdout for large file, got {res_exceeded.stdout}"
    finally:
        # Restore original db
        with open(db_path, "wb") as f:
            f.write(original_db)


def test_config_json():
    config_path = "/home/user/app_repo/config.json"
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{config_path} does not contain valid JSON."

    assert config.get("auth_port") == 8123, f"auth_port in config.json is not set to 8123 (got {config.get('auth_port')})."


def test_git_commit():
    repo_path = "/home/user/app_repo"
    res = subprocess.run(["git", "log", "-1", "--pretty=%B"], cwd=repo_path, capture_output=True, text=True)
    assert res.returncode == 0, "Failed to run git log. Is it a valid git repository?"
    assert "Fix pipeline" in res.stdout, f"The latest commit message does not contain 'Fix pipeline'. Got: {res.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
