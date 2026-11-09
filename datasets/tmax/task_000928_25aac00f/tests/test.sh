#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import subprocess
import tempfile


def test_auth_cpp_exists_and_fixed():
    path = "/home/user/auth.cpp"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "// AUTH_MODULE_START" in content, "auth.cpp is missing the start marker."
    assert "namespace Auth" in content, "auth.cpp does not contain the corrected 'namespace Auth'."
    assert "namespace Authentication" not in content, "auth.cpp still contains the incorrect 'namespace Authentication'."

    with open("/home/user/disk_image.bin", "rb") as f:
        image = f.read()
    start_marker = b"// AUTH_MODULE_START"
    end_marker = b"// AUTH_MODULE_END"
    start = image.find(start_marker)
    end = image.find(end_marker, start)
    assert start >= 0 and end >= 0, "Source markers are absent from disk_image.bin."
    recovered = image[start:end + len(end_marker)].decode("utf-8")
    expected = recovered.replace("namespace Authentication", "namespace Auth", 1)
    assert content.strip() == expected.strip(), "auth.cpp is not the recovered source with the required namespace correction."


def test_libauth_so_exists_and_exports_symbol():
    path = "/home/user/libauth.so"
    assert os.path.isfile(path), f"Shared library {path} does not exist."

    try:
        output = subprocess.check_output(["nm", "-D", path], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        output = e.output
    except FileNotFoundError:
        output = subprocess.check_output(["readelf", "-s", path], text=True)

    assert "_ZN4Auth12verify_tokenEiPKc" in output, f"Library {path} does not export the required symbol '_ZN4Auth12verify_tokenEiPKc'."

    with tempfile.TemporaryDirectory() as td:
        probe_cpp = os.path.join(td, "probe.cpp")
        probe_bin = os.path.join(td, "probe")
        with open(probe_cpp, "w", encoding="utf-8") as f:
            f.write(r'''#include <iostream>
namespace Auth { bool verify_token(int, const char*); }
int main() {
    std::cout << Auth::verify_token(0, "secret_token")
              << Auth::verify_token(1, "secret_token");
    return 0;
}
''')
        built = subprocess.run(
            ["g++", probe_cpp, path, "-Wl,-rpath,/home/user", "-o", probe_bin],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert built.returncode == 0, f"libauth.so could not be linked: {built.stderr}"
        run = subprocess.run(
            [probe_bin], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**os.environ, "LD_LIBRARY_PATH": "/home/user"}, timeout=10
        )
        assert run.returncode == 0, f"Calling verify_token failed: {run.stderr}"
        assert run.stdout == "01", "verify_token does not implement the recovered authentication behavior."

    service = subprocess.run(
        ["/home/user/auth_service"], cwd="/home/user",
        env={**os.environ, "LD_LIBRARY_PATH": "/home/user"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert service.returncode in (0, 1), (
        f"auth_service did not load and execute with libauth.so (exit {service.returncode}): "
        f"{service.stderr.decode(errors='replace')}"
    )


def test_reproduce_sh_exists_and_valid():
    path = "/home/user/reproduce.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "auth_service" in content, "reproduce.sh does not seem to execute auth_service."
    assert "status.log" in content, "reproduce.sh does not reference status.log."
    assert "CRASHED" in content, "reproduce.sh does not contain the word 'CRASHED'."


def test_status_log_contains_crashed():
    path = "/home/user/status.log"
    assert os.path.isfile(path), f"Log file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "CRASHED" in content, f"Log file {path} does not contain the word 'CRASHED'."


def test_reproduce_script_actually_runs_until_failure():
    service = "/home/user/auth_service"
    status = "/home/user/status.log"
    trace = "/tmp/auth_service_verifier_trace"
    counter = "/tmp/auth_service_verifier_count"

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "auth_service")
        shutil.copy2(service, backup)
        for p in (status, trace, counter):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass

        stub = r'''#!/bin/bash
n=0
if [ -f /tmp/auth_service_verifier_count ]; then
    n=$(cat /tmp/auth_service_verifier_count)
fi
n=$((n + 1))
printf '%s\n' "$n" > /tmp/auth_service_verifier_count
printf 'CALL|%s\n' "${LD_LIBRARY_PATH-}" >> /tmp/auth_service_verifier_trace
if [ "$n" -lt 3 ]; then
    exit 0
fi
exit 23
'''
        try:
            with open(service, "w", encoding="utf-8") as f:
                f.write(stub)
            os.chmod(service, 0o755)

            env = os.environ.copy()
            env.pop("LD_LIBRARY_PATH", None)
            proc = subprocess.Popen(
                ["/home/user/reproduce.sh"], cwd="/home/user", env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                start_new_session=True
            )
            try:
                stdout, stderr = proc.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate()
                raise AssertionError("reproduce.sh did not stop after auth_service failed.")

            assert proc.returncode == 0, f"reproduce.sh did not exit successfully: {stderr}"
            assert os.path.isfile(trace), "reproduce.sh never executed auth_service."
            with open(trace, "r", encoding="utf-8") as f:
                calls = [line.rstrip("\n") for line in f]
            assert len(calls) >= 3, "reproduce.sh did not repeatedly execute auth_service until it failed."
            for call in calls:
                _, ld_path = call.split("|", 1)
                assert "/home/user" in ld_path.split(":"), "reproduce.sh did not set LD_LIBRARY_PATH=/home/user."

            assert os.path.isfile(status), "reproduce.sh did not create status.log after the failure."
            with open(status, "r", encoding="utf-8") as f:
                lines = [line.strip() for line in f if line.strip()]
            assert lines == ["CRASHED"], "reproduce.sh did not append the exact word CRASHED upon failure."
        finally:
            shutil.copy2(backup, service)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
