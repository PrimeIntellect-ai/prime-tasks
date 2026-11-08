#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile


def test_setup_script_exists_and_executable():
    path = "/home/user/setup_observability.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_setup_script_execution_and_idempotency():
    setup_path = "/home/user/setup_observability.sh"

    result = subprocess.run([setup_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {setup_path} failed:\n{result.stderr}"

    assert os.path.isfile("/home/user/emitter"), "/home/user/emitter executable was not created."
    assert os.access("/home/user/emitter", os.X_OK), "/home/user/emitter is not executable."
    with open("/home/user/emitter", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/emitter is not a compiled executable."

    assert os.path.isdir("/home/user/dashboard_metrics"), "/home/user/dashboard_metrics directory was not created."

    wrapper_path = "/home/user/run_emitter.sh"
    assert os.path.isfile(wrapper_path), f"{wrapper_path} was not created."
    assert os.access(wrapper_path, os.X_OK), f"{wrapper_path} is not executable."

    result2 = subprocess.run([setup_path], capture_output=True, text=True)
    assert result2.returncode == 0, f"Running {setup_path} a second time failed."

    with open(wrapper_path, "r") as f:
        lines = f.readlines()
    assert len(lines) < 20, f"{wrapper_path} grew too large, setup script is likely not idempotent."


def test_emitter_behavior_missing_env():
    env = os.environ.copy()
    env.pop("METRICS_OUT_DIR", None)

    result = subprocess.run(["/home/user/emitter"], env=env, capture_output=True, text=True)
    assert result.returncode != 0, "emitter should exit with a non-zero code when METRICS_OUT_DIR is missing."
    assert result.stderr.strip() != "", "emitter should print an error message to stderr when METRICS_OUT_DIR is missing."


def test_emitter_uses_nondefault_environment_directory_and_appends():
    with tempfile.TemporaryDirectory(prefix="emitter-test-") as root:
        output_dir = os.path.join(root, "custom metrics")
        working_dir = os.path.join(root, "working")
        os.mkdir(output_dir)
        os.mkdir(working_dir)

        env = os.environ.copy()
        env["METRICS_OUT_DIR"] = output_dir
        expected_log = os.path.join(output_dir, "health.log")

        first = subprocess.run(
            ["/home/user/emitter"], env=env, cwd=working_dir,
            capture_output=True, text=True
        )
        assert first.returncode == 0, f"emitter failed with a custom METRICS_OUT_DIR:\n{first.stderr}"
        assert os.path.isfile(expected_log), "emitter did not create <METRICS_OUT_DIR>/health.log."
        assert not os.path.exists(os.path.join(working_dir, "health.log")), "emitter wrote health.log in its current working directory."
        with open(expected_log, "rb") as f:
            assert f.read() == b"status=OK\n", "emitter did not write exactly 'status=OK\\n'."

        second = subprocess.run(
            ["/home/user/emitter"], env=env, cwd=working_dir,
            capture_output=True, text=True
        )
        assert second.returncode == 0, f"second emitter invocation failed:\n{second.stderr}"
        with open(expected_log, "rb") as f:
            assert f.read() == b"status=OK\nstatus=OK\n", "emitter must append one status line per invocation."


def test_modified_c_source_independently_compiles_and_uses_environment():
    source = "/home/user/emitter.c"
    assert os.path.isfile(source), f"{source} does not exist."

    with tempfile.TemporaryDirectory(prefix="source-test-") as root:
        probe = os.path.join(root, "compiled-emitter")
        output_dir = os.path.join(root, "output")
        os.mkdir(output_dir)

        compile_result = subprocess.run(
            ["gcc", source, "-o", probe], capture_output=True, text=True
        )
        assert compile_result.returncode == 0, f"emitter.c did not compile:\n{compile_result.stderr}"

        env = os.environ.copy()
        env["METRICS_OUT_DIR"] = output_dir
        result = subprocess.run([probe], env=env, cwd=root, capture_output=True, text=True)
        assert result.returncode == 0, f"Program compiled from emitter.c failed:\n{result.stderr}"

        expected_log = os.path.join(output_dir, "health.log")
        assert os.path.isfile(expected_log), "Program compiled from emitter.c ignored METRICS_OUT_DIR."
        with open(expected_log, "rb") as f:
            assert f.read() == b"status=OK\n", "Program compiled from emitter.c wrote incorrect content."


def test_wrapper_script_behavior():
    wrapper_path = "/home/user/run_emitter.sh"
    log_path = "/home/user/dashboard_metrics/health.log"

    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run([wrapper_path], capture_output=True, text=True)
    assert result.returncode == 0, f"{wrapper_path} failed to execute properly."

    assert os.path.isfile(log_path), f"{log_path} was not created by the wrapper script."

    with open(log_path, "r") as f:
        content = f.read()

    assert "status=OK" in content, f"{log_path} does not contain 'status=OK'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
