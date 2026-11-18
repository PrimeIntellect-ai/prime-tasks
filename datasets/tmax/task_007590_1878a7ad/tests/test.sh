#!/bin/bash
set -e
mkdir -p /logs/verifier

# A pre-created log must not satisfy the execution checks.
rm -f /home/user/state/mount_state.log /tmp/state/mount_state.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid


def test_fstab_created():
    """Check if my_fstab was created with the correct content."""
    fstab_path = "/home/user/my_fstab"
    assert os.path.isfile(fstab_path), f"Missing custom fstab at {fstab_path}"

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    assert "sysfs /home/user/sys_mnt sysfs defaults 0 0" in content, "The fstab file does not contain the correct mount entry."


def test_bashrc_updated():
    """Check if .bashrc was updated with the required environment variables."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"Missing .bashrc at {bashrc_path}"

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "FSTAB_PATH=/home/user/my_fstab" in content, ".bashrc is missing FSTAB_PATH export."
    assert "STATE_DIR=/home/user/state" in content, ".bashrc is missing STATE_DIR export."


def test_rust_code_fixed():
    """Check if the Rust code was modified to read STATE_DIR from the environment."""
    main_rs_path = "/home/user/mounter/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Missing main.rs at {main_rs_path}"

    with open(main_rs_path, "r") as f:
        content = f.read()

    assert 'env::var("STATE_DIR")' in content, "Rust code does not read STATE_DIR from the environment."
    assert "/tmp/state" not in content, "Rust code still contains the hardcoded /tmp/state directory."


def test_wrapper_script():
    """Check if start_service.sh exists, is executable, sources .bashrc, and runs the project."""
    script_path = "/home/user/start_service.sh"
    assert os.path.isfile(script_path), f"Missing wrapper script at {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    has_source = "source /home/user/.bashrc" in content or ". /home/user/.bashrc" in content
    assert has_source, "Wrapper script does not source /home/user/.bashrc."

    has_cargo = "cargo run" in content or "cargo build" in content or "mounter" in content
    assert has_cargo, "Wrapper script does not seem to build/execute the Rust project."


def _run_wrapper():
    result = subprocess.run(
        ["/home/user/start_service.sh"],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Wrapper failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_wrapper_builds_and_executes_service():
    """Run the wrapper on a verifier-generated entry and require its derived output."""
    fstab_path = "/home/user/my_fstab"
    log_path = "/home/user/state/mount_state.log"
    target_path = "/home/user/mounter/target"

    with open(fstab_path, "r") as f:
        original_fstab = f.read()

    probe = uuid.uuid4().hex
    mount_point = f"/home/user/probe_{probe}"
    probe_entry = f"tmpfs {mount_point} tmpfs defaults 0 0\n"
    expected_probe = f"Simulated mounting tmpfs on {mount_point}"

    try:
        with open(fstab_path, "w") as f:
            f.write(probe_entry)
        if os.path.exists(log_path):
            os.remove(log_path)
        shutil.rmtree(target_path, ignore_errors=True)

        _run_wrapper()

        assert os.path.isfile(log_path), "Wrapper did not create the state log."
        with open(log_path, "r") as f:
            actual = f.read().strip()
        assert actual == expected_probe, (
            "Wrapper did not execute the service against the verifier-generated fstab. "
            f"Expected {expected_probe!r}, found {actual!r}."
        )

        built_mounter = []
        if os.path.isdir(target_path):
            for root, _, files in os.walk(target_path):
                if "mounter" in files:
                    candidate = os.path.join(root, "mounter")
                    if os.access(candidate, os.X_OK):
                        built_mounter.append(candidate)
        assert built_mounter, "The wrapper did not build the Rust mounter project."
    finally:
        with open(fstab_path, "w") as f:
            f.write(original_fstab)

    # Execute once more with the required final fstab so the required final log remains.
    if os.path.exists(log_path):
        os.remove(log_path)
    _run_wrapper()


def test_compiled_service_uses_runtime_environment():
    """Build and exercise the Rust artifact with unpredictable verifier-owned paths."""
    build = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd="/home/user/mounter",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust project failed to build:\n{build.stdout}\n{build.stderr}"

    binary = "/home/user/mounter/target/debug/mounter"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Cargo did not produce an executable mounter binary."

    probe_root = f"/tmp/mounter_verify_{uuid.uuid4().hex}"
    state_dir = os.path.join(probe_root, "state")
    fstab_path = os.path.join(probe_root, "fstab")
    mount_point = os.path.join(probe_root, "mount")
    os.makedirs(probe_root)
    with open(fstab_path, "w") as f:
        f.write(f"proc {mount_point} proc defaults 0 0\n")

    runtime_env = {
        "HOME": "/home/user",
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "FSTAB_PATH": fstab_path,
        "STATE_DIR": state_dir,
    }
    result = subprocess.run(
        [binary], env=runtime_env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"Compiled service failed:\n{result.stdout}\n{result.stderr}"

    generated_log = os.path.join(state_dir, "mount_state.log")
    expected = f"Simulated mounting proc on {mount_point}"
    assert os.path.isfile(generated_log), "Service did not write to the STATE_DIR supplied at runtime."
    with open(generated_log, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Unexpected runtime-derived log: {actual!r}"

    # STATE_DIR is mandatory: with a valid fstab but no STATE_DIR, the program must panic/fail.
    no_state_env = {
        "HOME": "/home/user",
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "FSTAB_PATH": fstab_path,
    }
    missing_state = subprocess.run(
        [binary], env=no_state_env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert missing_state.returncode != 0, "Service succeeded even though STATE_DIR was unset."
    assert not os.path.exists("/tmp/state/mount_state.log"), "Service fell back to the forbidden /tmp/state path."


def test_log_created():
    """Check if the log file was created with the correct output."""
    log_path = "/home/user/state/mount_state.log"
    assert os.path.isfile(log_path), f"Missing log file at {log_path}. Did the service run successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_log = "Simulated mounting sysfs on /home/user/sys_mnt"
    assert expected_log in content, f"Log file does not contain the expected message. Found: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
