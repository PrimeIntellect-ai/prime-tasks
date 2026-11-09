#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess

BASE_DIR = "/home/user/build_project"
SRC_DIR = os.path.join(BASE_DIR, "src")
APP = os.path.join(BASE_DIR, "dist", "app.sh")
CACHE = os.path.join(BASE_DIR, "cache")
FUZZ = os.path.join(BASE_DIR, "fuzz.sh")
REPORT = os.path.join(BASE_DIR, "report.txt")


def empty_cache():
    for name in os.listdir(CACHE):
        path = os.path.join(CACHE, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def run_fuzz(env=None):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        ["bash", FUZZ], cwd=BASE_DIR, env=merged,
        capture_output=True, text=True, timeout=30
    )


def test_patch_applied():
    """Test that the patch was applied to core.sh."""
    core_sh = os.path.join(BASE_DIR, "src", "core.sh")
    assert os.path.isfile(core_sh), f"{core_sh} does not exist."

    with open(core_sh, "r") as f:
        content = f.read()

    assert "VULN=1" not in content, "Patch was not applied: VULN=1 still found in core.sh."
    assert "VULN=0" in content, "Patch was not applied: VULN=0 not found in core.sh."


def test_build_order_in_app_sh():
    """Execute build.sh and verify that it really builds the required artifact."""
    build_sh = os.path.join(BASE_DIR, "build.sh")
    assert os.path.isfile(build_sh), f"{build_sh} does not exist."

    if os.path.lexists(APP):
        os.unlink(APP)
    result = subprocess.run(
        ["bash", build_sh], cwd=BASE_DIR,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(APP), f"{APP} does not exist."

    with open(APP, "r") as f:
        content = f.read()

    assert "log_msg() {" in content, "app.sh is missing utils.sh content."
    assert "validate_input()" in content, "app.sh is missing core.sh content."
    assert "main()" in content, "app.sh is missing main.sh content."

    util_idx = content.find("log_msg() {")
    core_idx = content.find("validate_input()")
    main_idx = content.find("main()")

    assert util_idx < core_idx, "Incorrect build order: utils.sh must precede core.sh."
    assert core_idx < main_idx, "Incorrect build order: core.sh must precede main.sh."
    assert os.access(APP, os.X_OK), "dist/app.sh is not executable."

    expected = b""
    for name in ("utils.sh", "core.sh", "main.sh"):
        with open(os.path.join(SRC_DIR, name), "rb") as f:
            expected += f.read()
    with open(APP, "rb") as f:
        actual = f.read()
    assert actual == expected, (
        "build.sh did not concatenate utils.sh, core.sh, and main.sh exactly in the required order."
    )


def test_fuzz_script_runs_50_randomized_trials_and_checks_failures():
    assert os.path.isfile(FUZZ), f"{FUZZ} does not exist."
    syntax = subprocess.run(["bash", "-n", FUZZ], capture_output=True, text=True)
    assert syntax.returncode == 0, f"fuzz.sh has invalid Bash syntax: {syntax.stderr}"
    with open(FUZZ, "r") as f:
        fuzz_content = f.read()
    assert re.search(r"\$(?:\{RANDOM\}|RANDOM\b)", fuzz_content), (
        "fuzz.sh must use Bash's $RANDOM for trial arguments."
    )

    with open(APP, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(APP).st_mode)
    real_app = APP + ".verifier-real"
    log = "/tmp/fuzz-invocations.log"

    try:
        with open(real_app, "wb") as f:
            f.write(original)
        os.chmod(real_app, original_mode)

        wrapper = '''#!/bin/bash
printf '%s\\n' "$1" >> "$FUZZ_LOG"
exec "$FUZZ_REAL_APP" "$@"
'''
        with open(APP, "w") as f:
            f.write(wrapper)
        os.chmod(APP, 0o755)

        empty_cache()
        for path in (REPORT, log):
            if os.path.exists(path):
                os.unlink(path)
        result = run_fuzz({"FUZZ_LOG": log, "FUZZ_REAL_APP": real_app})
        assert result.returncode == 0, (
            f"fuzz.sh failed against the working artifact: {result.stdout}{result.stderr}"
        )
        assert os.path.isfile(log), "fuzz.sh did not execute dist/app.sh."
        with open(log, "r") as f:
            args = [line.rstrip("\n") for line in f]
        assert len(args) == 50, f"fuzz.sh must run dist/app.sh 50 times; observed {len(args)}."
        assert all(re.fullmatch(r"[0-9]+", arg) for arg in args), (
            "fuzz.sh did not pass integer arguments to every trial."
        )
        assert all(0 <= int(arg) <= 32767 for arg in args), (
            "Trial arguments are not values produced by Bash $RANDOM."
        )
        assert len(set(args)) >= 40, "fuzz.sh did not use different randomized arguments across trials."
        assert os.listdir(CACHE) == [], "fuzz.sh succeeded while the cache was not empty."
        assert os.path.isfile(REPORT), "report.txt was not generated by a successful fuzz.sh run."
        with open(REPORT, "r") as f:
            assert f.read().strip() == "FUZZING SUCCESS"

        # It must stop immediately when the application exits unsuccessfully.
        for path in (REPORT, log):
            if os.path.exists(path):
                os.unlink(path)
        with open(APP, "w") as f:
            f.write('#!/bin/bash\nprintf "%s\\n" "$1" >> "$FUZZ_LOG"\nexit 7\n')
        os.chmod(APP, 0o755)
        empty_cache()
        result = run_fuzz({"FUZZ_LOG": log})
        assert result.returncode != 0, "fuzz.sh ignored a failing dist/app.sh trial."
        with open(log, "r") as f:
            calls = f.readlines()
        assert len(calls) == 1, "fuzz.sh did not exit immediately after a failed trial."
        assert not os.path.exists(REPORT), "fuzz.sh wrote a success report after a failed trial."

        # It must also stop immediately when a successful application leaks a file.
        for path in (REPORT, log):
            if os.path.exists(path):
                os.unlink(path)
        with open(APP, "w") as f:
            f.write('#!/bin/bash\nprintf "%s\\n" "$1" >> "$FUZZ_LOG"\ntouch /home/user/build_project/cache/verifier-leak\nexit 0\n')
        os.chmod(APP, 0o755)
        empty_cache()
        result = run_fuzz({"FUZZ_LOG": log})
        assert result.returncode != 0, "fuzz.sh ignored a non-empty cache directory."
        with open(log, "r") as f:
            calls = f.readlines()
        assert len(calls) == 1, "fuzz.sh did not exit immediately after detecting a cache leak."
        assert not os.path.exists(REPORT), "fuzz.sh wrote a success report after a cache leak."
    finally:
        with open(APP, "wb") as f:
            f.write(original)
        os.chmod(APP, original_mode)
        if os.path.exists(real_app):
            os.unlink(real_app)
        if os.path.exists(log):
            os.unlink(log)
        empty_cache()

    # Regenerate the required final report using the restored real artifact.
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = run_fuzz()
    assert result.returncode == 0, f"Final fuzz.sh run failed: {result.stdout}{result.stderr}"


def test_fuzzing_report():
    """Test that report.txt exists and contains the correct string."""
    assert os.path.isfile(REPORT), "report.txt was not generated."
    with open(REPORT, "r") as f:
        content = f.read().strip()
    assert content == "FUZZING SUCCESS", f"report.txt content is incorrect. Expected 'FUZZING SUCCESS', got '{content}'."


def test_resource_leak_fixed():
    """Test cleanup for the original fixed input and many verifier-chosen inputs."""
    assert os.path.isfile(APP), f"{APP} does not exist."
    assert os.path.isdir(CACHE), f"{CACHE} does not exist."

    empty_cache()
    result = subprocess.run([APP, "99999"], capture_output=True, text=True)
    assert result.returncode == 0, f"app.sh failed with exit code {result.returncode}."
    files_in_cache = os.listdir(CACHE)
    assert len(files_in_cache) == 0, f"Resource leak detected: cache directory is not empty. Found: {files_in_cache}"

    values = set()
    while len(values) < 50:
        values.add(secrets.randbelow(2_000_000_000) + 1)
    for value in values:
        result = subprocess.run([APP, str(value)], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"app.sh failed for verifier-selected input {value}."
        files_in_cache = os.listdir(CACHE)
        assert files_in_cache == [], (
            f"Resource leak detected for input {value}. Found: {files_in_cache}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
