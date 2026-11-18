#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shlex
import shutil
import signal
import subprocess
import time
import uuid


def stop_supervisors():
    subprocess.run(["pkill", "-f", "/home/user/run_service.sh"], capture_output=True)
    time.sleep(0.3)


def cargo_was_called(marker):
    if not os.path.isfile(marker):
        return False
    with open(marker, "r") as f:
        lines = f.read().splitlines()
    for line in lines:
        try:
            cwd, args = line.split("\t", 1)
        except ValueError:
            continue
        if cwd == "/home/user/user-mngr" and args.split() == ["build", "--release"]:
            return True
    return False


def test_deploy_and_service():
    deploy_script = "/home/user/deploy.sh"
    run_service_script = "/home/user/run_service.sh"
    marker = "/tmp/verifier-cargo-calls"
    wrapper_dir = "/tmp/verifier-bin"
    real_cargo = shutil.which("cargo")
    probe_proc = None

    try:
        assert os.path.isfile(deploy_script), f"{deploy_script} does not exist"
        assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable"

        assert os.path.isfile(run_service_script), f"{run_service_script} does not exist"
        assert os.access(run_service_script, os.X_OK), f"{run_service_script} is not executable"

        assert real_cargo, "cargo is unavailable"
        assert os.path.isfile("/home/user/user-mngr/Cargo.toml"), "Cargo.toml does not exist"
        assert os.path.isfile("/home/user/user-mngr/src/main.rs"), "Rust worker source does not exist"

        stop_supervisors()
        os.makedirs(wrapper_dir, exist_ok=True)
        cargo_wrapper = os.path.join(wrapper_dir, "cargo")
        with open(cargo_wrapper, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s\\t%s\\n' \"$PWD\" \"$*\" >> /tmp/verifier-cargo-calls\n")
            f.write("if [ \"${CARGO_VERIFIER_FAIL:-}\" = 1 ]; then exit 97; fi\n")
            f.write(f"exec {shlex.quote(real_cargo)} \"$@\"\n")
        os.chmod(cargo_wrapper, 0o755)

        base_env = os.environ.copy()
        base_env["PATH"] = wrapper_dir + os.pathsep + base_env.get("PATH", "")

        # A failed Cargo build must cause deploy.sh itself to fail.
        if os.path.exists(marker):
            os.unlink(marker)
        fail_env = base_env.copy()
        fail_env["CARGO_VERIFIER_FAIL"] = "1"
        failed = subprocess.run([deploy_script], capture_output=True, text=True,
                                env=fail_env, timeout=30)
        assert cargo_was_called(marker), "deploy.sh did not run 'cargo build --release' from the project directory"
        assert failed.returncode != 0, "deploy.sh did not fail when cargo build failed"

        stop_supervisors()
        if os.path.exists(marker):
            os.unlink(marker)
        shutil.rmtree("/home/user/user-mngr/target", ignore_errors=True)
        shutil.rmtree("/home/user/bin", ignore_errors=True)

        # Run deploy.sh with no existing build artifact, forcing a real build.
        result = subprocess.run([deploy_script], capture_output=True, text=True,
                                env=base_env, timeout=180)
        assert result.returncode == 0, f"deploy.sh failed with exit code {result.returncode}\nstdout: {result.stdout}\nstderr: {result.stderr}"
        assert cargo_was_called(marker), "deploy.sh did not run 'cargo build --release' from the project directory"

        # Check if binary was copied.
        deployed_binary = "/home/user/bin/user-mngr"
        release_binary = "/home/user/user-mngr/target/release/user-mngr"
        assert os.path.isfile(deployed_binary), "/home/user/bin/user-mngr was not created by deploy.sh"
        assert os.access(deployed_binary, os.X_OK), "/home/user/bin/user-mngr is not executable"
        assert os.path.isfile(release_binary), "cargo release artifact was not created"
        with open(deployed_binary, "rb") as f:
            deployed_hash = hashlib.sha256(f.read()).digest()
        with open(release_binary, "rb") as f:
            release_hash = hashlib.sha256(f.read()).digest()
        assert deployed_hash == release_hash, "deployed executable is not the Cargo-built Rust worker"

        # Wait briefly for service to start.
        time.sleep(1)

        # Preserve the original end-to-end service assertions.
        queue_dir = "/home/user/queue"
        request_file = os.path.join(queue_dir, "request.txt")
        os.makedirs(queue_dir, exist_ok=True)
        for u in ["testuser1", "testuser2"]:
            shutil.rmtree(f"/home/user/homes/{u}", ignore_errors=True)
        with open(request_file, "w") as f:
            f.write("testuser1\ntestuser2\n")

        time.sleep(3)
        assert not os.path.exists(request_file), f"{request_file} was not deleted after processing"

        for u in ["testuser1", "testuser2"]:
            user_dir = f"/home/user/homes/{u}"
            assert os.path.isdir(user_dir), f"Directory {user_dir} was not created"
            readme_file = os.path.join(user_dir, "readme.txt")
            assert os.path.isfile(readme_file), f"File {readme_file} was not created"
            with open(readme_file, "r") as f:
                content = f.read().strip()
            assert content == f"Welcome {u}", f"Incorrect content in {readme_file}: expected 'Welcome {u}', got '{content}'"

        stop_supervisors()

        # Exercise the deployed worker directly with unpredictable usernames.
        users = ["audit_" + uuid.uuid4().hex, "audit_" + uuid.uuid4().hex]
        for u in users:
            shutil.rmtree(f"/home/user/homes/{u}", ignore_errors=True)
        with open(request_file, "w") as f:
            f.write("\n".join(users) + "\n")
        worker = subprocess.run([deployed_binary], capture_output=True, text=True, timeout=10)
        assert worker.returncode == 0, f"deployed worker failed: {worker.stderr}"
        assert not os.path.exists(request_file), "deployed worker did not delete request.txt"
        for u in users:
            readme = f"/home/user/homes/{u}/readme.txt"
            assert os.path.isdir(f"/home/user/homes/{u}"), f"worker did not create home for {u}"
            assert os.path.isfile(readme), f"worker did not create readme for {u}"
            with open(readme, "rb") as f:
                assert f.read() == f"Welcome {u}".encode(), f"readme for {u} does not contain the exact required text"
        no_request = subprocess.run([deployed_binary], capture_output=True, text=True, timeout=10)
        assert no_request.returncode == 0, "worker did not exit successfully when request.txt was absent"

        # Replace the deployed path with a probe and run the supervisor itself.
        # Repeated probe calls demonstrate that it loops, invokes the exact path,
        # and waits approximately one second after each invocation.
        probe_log = "/tmp/user-mngr-probe.log"
        if os.path.exists(probe_log):
            os.unlink(probe_log)
        with open(deployed_binary, "w") as f:
            f.write("#!/bin/bash\ndate +%s.%N >> /tmp/user-mngr-probe.log\nexit 0\n")
        os.chmod(deployed_binary, 0o755)

        probe_proc = subprocess.Popen([run_service_script], stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(2.7)
        assert probe_proc.poll() is None, "run_service.sh did not remain running in an infinite loop"
        assert os.path.isfile(probe_log), "run_service.sh did not execute /home/user/bin/user-mngr"
        with open(probe_log, "r") as f:
            stamps = [float(x) for x in f.read().splitlines() if x.strip()]
        assert len(stamps) >= 3, "run_service.sh did not repeatedly invoke the deployed binary"
        for delta in [b - a for a, b in zip(stamps[:3], stamps[1:3])]:
            assert 0.85 <= delta <= 1.6, f"run_service.sh did not sleep 1 between executions (interval {delta:.3f}s)"

        # Cleanup running supervisor to prevent dangling processes.
        subprocess.run(["pkill", "-f", "run_service.sh"], capture_output=True)
    finally:
        if probe_proc is not None and probe_proc.poll() is None:
            try:
                os.killpg(probe_proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        stop_supervisors()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
