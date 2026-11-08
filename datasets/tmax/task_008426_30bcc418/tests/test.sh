#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile


def run_e2e():
    result = subprocess.run(
        ["python3", "/home/user/e2e_test.py"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"e2e_test.py failed with return code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert "Success! Feature works." in result.stdout, (
        "e2e_test.py did not print the success message."
    )


def test_final_state_and_resolver_behavior():
    script_path = "/home/user/resolve.sh"
    active_dir = "/home/user/active_libs"
    pool_dir = "/home/user/libpool"
    log_path = "/home/user/solution.log"

    # Preserve the original verifier's assertions about the submitted state.
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    original_expected = {
        "libA.so": "libA_v1.so",
        "libB.so": "libB_v1.so",
        "libC.so": "libC_v1.so",
        "libD.so": "libD_v1.so",
    }
    for link_name, target_name in original_expected.items():
        link_path = os.path.join(active_dir, link_name)
        assert os.path.islink(link_path), f"{link_path} is missing or is not a symlink."
        target = os.readlink(link_path)
        assert target_name in target, f"Symlink {link_path} does not point to {target_name}."

    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = ["libA_v1.so", "libB_v1.so", "libC_v1.so", "libD_v1.so"]
    assert lines == expected_lines, (
        f"Content of {log_path} is incorrect. Expected {expected_lines}, got {lines}."
    )
    run_e2e()

    # Build a fresh challenge using the same library artifacts but unpredictable
    # version names. The working dependency chain is deliberately given unrelated
    # version numbers, so selecting a fixed version or matching numbers cannot pass.
    with tempfile.TemporaryDirectory() as backup:
        for family in "ABCD":
            for version in (1, 2):
                src = os.path.join(pool_dir, f"lib{family}_v{version}.so")
                assert os.path.isfile(src), f"Required test artifact is missing: {src}"
                shutil.copy2(src, os.path.join(backup, f"lib{family}_v{version}.so"))

        for name in os.listdir(pool_dir):
            path = os.path.join(pool_dir, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

        versions = iter(secrets.SystemRandom().sample(range(100, 1000), 8))
        expected_dynamic = {}
        for family in "ABCD":
            good_version = next(versions)
            bad_version = next(versions)
            good_name = f"lib{family}_v{good_version}.so"
            bad_name = f"lib{family}_v{bad_version}.so"
            shutil.copy2(
                os.path.join(backup, f"lib{family}_v1.so"),
                os.path.join(pool_dir, good_name),
            )
            shutil.copy2(
                os.path.join(backup, f"lib{family}_v2.so"),
                os.path.join(pool_dir, bad_name),
            )
            expected_dynamic[f"lib{family}.so"] = good_name

    os.makedirs(active_dir, exist_ok=True)
    for name in os.listdir(active_dir):
        path = os.path.join(active_dir, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    stale_path = os.path.join(active_dir, "stale-file")
    with open(stale_path, "w") as f:
        f.write("must be cleared")
    with open(log_path, "w") as f:
        f.write("stale-log\n")

    # Install a trusted equivalent of the required end-to-end test with a marker,
    # allowing the verifier to prove that resolve.sh itself executed the test.
    marker = f"/tmp/resolve-e2e-{secrets.token_hex(12)}"
    marker_value = secrets.token_hex(16)
    e2e_source = f'''import ctypes
import os
import sys

try:
    lib = ctypes.CDLL(os.path.join("/home/user/active_libs", "libA.so"), mode=ctypes.RTLD_GLOBAL)
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libB.so"), mode=ctypes.RTLD_GLOBAL)
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libC.so"), mode=ctypes.RTLD_GLOBAL)
    ctypes.CDLL(os.path.join("/home/user/active_libs", "libD.so"), mode=ctypes.RTLD_GLOBAL)
    res = lib.A_entry()
    if res == 42:
        with open({marker!r}, "w") as marker_file:
            marker_file.write({marker_value!r})
        print("Success! Feature works.")
        sys.exit(0)
    print(f"Failed. Expected 42, got {{res}}")
    sys.exit(1)
except Exception as e:
    print(f"Error: {{e}}")
    sys.exit(1)
'''
    with open("/home/user/e2e_test.py", "w") as f:
        f.write(e2e_source)
    os.chmod("/home/user/e2e_test.py", 0o755)

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"resolve.sh failed with return code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert not os.path.exists(stale_path), "resolve.sh did not clear active_libs."
    assert os.path.isfile(marker), "resolve.sh did not execute the end-to-end test successfully."
    with open(marker, "r") as f:
        assert f.read() == marker_value, "The end-to-end execution marker is invalid."

    for link_name, target_name in expected_dynamic.items():
        link_path = os.path.join(active_dir, link_name)
        assert os.path.islink(link_path), f"{link_path} is missing or is not a symlink."
        target_path = os.path.realpath(link_path)
        expected_path = os.path.realpath(os.path.join(pool_dir, target_name))
        assert target_path == expected_path, (
            f"{link_path} points to {target_path}, expected {expected_path}."
        )

    with open(log_path, "r") as f:
        dynamic_lines = [line.strip() for line in f if line.strip()]
    expected_log = sorted(expected_dynamic.values())
    assert dynamic_lines == expected_log, (
        f"Content of {log_path} is incorrect. Expected {expected_log}, got {dynamic_lines}."
    )
    run_e2e()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
