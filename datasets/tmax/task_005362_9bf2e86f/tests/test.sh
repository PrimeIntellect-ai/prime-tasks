#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

PROVISION = "/home/user/provision.exp"
SUPERVISOR = "/home/user/supervisor.sh"
SERVICE = "/home/user/service.sh"
INSTALLER = "/home/user/app-installer.sh"
VOLUME = "/home/user/volume"
LOG = "/home/user/supervisor.log"
EXPECTED = "[QUOTA ENFORCED] Restarted prod-worker"


def stop_existing_processes():
    subprocess.run(["pkill", "-TERM", "-f", "^(/bin/)?bash /home/user/supervisor.sh"], check=False)
    subprocess.run(["pkill", "-TERM", "-f", "^(/bin/)?bash /home/user/service.sh"], check=False)
    time.sleep(0.3)


def test_provision_script_exists():
    assert os.path.isfile(PROVISION), f"Verification failed: {PROVISION} not found."


def test_supervisor_script_exists():
    assert os.path.isfile(SUPERVISOR), f"Verification failed: {SUPERVISOR} not found."


def test_service_installed():
    assert os.path.isfile(SERVICE), f"Verification failed: {SERVICE} not found. The app-installer.sh may not have been run successfully."
    assert os.access(SERVICE, os.X_OK), f"Verification failed: {SERVICE} is not executable."


def test_supervisor_log():
    assert os.path.isfile(LOG), f"Verification failed: {LOG} not found."
    with open(LOG, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 3, f"Verification failed: {LOG} should have exactly 3 lines, found {len(lines)}."
    for i, line in enumerate(lines):
        assert line == EXPECTED, f"Verification failed: Log line {i+1} mismatch. Expected '{EXPECTED}', got '{line}'."


def test_provision_script_drives_interactive_installer():
    stop_existing_processes()
    nonce = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as backup:
        installer_backup = os.path.join(backup, "installer")
        shutil.copy2(INSTALLER, installer_backup)
        service_existed = os.path.exists(SERVICE)
        if service_existed:
            shutil.copy2(SERVICE, os.path.join(backup, "service"))
        volume_existed = os.path.isdir(VOLUME)
        if volume_existed:
            shutil.copytree(VOLUME, os.path.join(backup, "volume"))

        marker = os.path.join(backup, "installer-ran")
        answers = os.path.join(backup, "answers")
        probe = f'''#!/bin/bash
read -p "Enter instance name: " inst
read -p "Enter port number: " port
read -p "Enable verbose mode? (y/n): " verb
printf '%s\\n%s\\n%s\\n' "$inst" "$port" "$verb" > {answers!r}
if [ "$inst" = prod-worker ] && [ "$port" = 9090 ] && [ "$verb" = y ]; then
    printf '%s' {nonce!r} > {marker!r}
    mkdir -p /home/user/volume
    cat > /home/user/service.sh <<'EOS'
#!/bin/bash
exit 0
EOS
    chmod +x /home/user/service.sh
    exit 0
fi
exit 23
'''
        try:
            with open(INSTALLER, "w") as f:
                f.write(probe)
            os.chmod(INSTALLER, 0o755)
            if os.path.lexists(SERVICE):
                os.remove(SERVICE)
            shutil.rmtree(VOLUME, ignore_errors=True)

            result = subprocess.run(
                ["/usr/bin/expect", PROVISION],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=12,
            )
            assert result.returncode == 0, f"provision.exp failed when executed by Expect:\n{result.stdout}"
            assert os.path.isfile(marker), "provision.exp did not execute the interactive installer successfully."
            assert open(marker).read() == nonce
            assert open(answers).read().splitlines() == ["prod-worker", "9090", "y"], "Installer received incorrect responses."
            assert os.path.isfile(SERVICE) and os.access(SERVICE, os.X_OK), "Installer did not generate an executable service.sh."
            assert os.path.isdir(VOLUME), "Installer did not generate the volume directory."
        finally:
            shutil.copy2(installer_backup, INSTALLER)
            if os.path.lexists(SERVICE):
                os.remove(SERVICE)
            if service_existed:
                shutil.copy2(os.path.join(backup, "service"), SERVICE)
            shutil.rmtree(VOLUME, ignore_errors=True)
            if volume_existed:
                shutil.copytree(os.path.join(backup, "volume"), VOLUME)


def test_supervisor_enforces_quota_clears_and_restarts():
    stop_existing_processes()
    with tempfile.TemporaryDirectory() as backup:
        shutil.copy2(SERVICE, os.path.join(backup, "service"))
        log_existed = os.path.exists(LOG)
        if log_existed:
            shutil.copy2(LOG, os.path.join(backup, "log"))
        volume_existed = os.path.isdir(VOLUME)
        if volume_existed:
            shutil.copytree(VOLUME, os.path.join(backup, "volume"))

        starts = os.path.join(backup, "starts")
        terms = os.path.join(backup, "terms")
        fixture = f'''#!/bin/bash
set -e
mkdir -p /home/user/volume
echo $$ >> {starts!r}
trap 'echo $$ >> {terms!r}; exit 0' TERM INT
file=/home/user/volume/run_$$.bin
dd if=/dev/zero of="$file" bs=1024 count=48 status=none
sleep 1.2
dd if=/dev/zero of="$file" bs=1024 count=16 seek=48 conv=notrunc status=none
while true; do sleep 0.1; done
'''
        proc = None
        started_at = time.monotonic()
        observed_lines = []
        observed_starts = []
        observed_terms = []
        observed_files = []
        try:
            with open(SERVICE, "w") as f:
                f.write(fixture)
            os.chmod(SERVICE, 0o755)
            shutil.rmtree(VOLUME, ignore_errors=True)
            os.mkdir(VOLUME)
            if os.path.exists(LOG):
                os.remove(LOG)

            proc = subprocess.Popen(
                ["/bin/bash", SUPERVISOR],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if os.path.isfile(LOG):
                    with open(LOG) as f:
                        observed_lines = f.read().splitlines()
                    if len(observed_lines) >= 3:
                        break
                if proc.poll() is not None:
                    break
                time.sleep(0.1)

            restart_deadline = time.monotonic() + 2
            while time.monotonic() < restart_deadline:
                if os.path.exists(starts):
                    observed_starts = open(starts).read().splitlines()
                if len(observed_starts) >= 4:
                    break
                time.sleep(0.05)

            elapsed = time.monotonic() - started_at
            if os.path.exists(terms):
                observed_terms = open(terms).read().splitlines()
            observed_files = os.listdir(VOLUME)

            assert observed_lines == [EXPECTED, EXPECTED, EXPECTED], "Supervisor must produce exactly three genuine quota-enforcement log entries."
            assert elapsed >= 4.0, "Supervisor logged quota events before the test service exceeded the quota."
            assert len(observed_starts) >= 4, "Supervisor did not start the service initially and restart it after all three events."
            assert all(pid in observed_terms for pid in observed_starts[:3]), "Supervisor did not terminate each over-quota service process."
            assert all(f"run_{pid}.bin" not in observed_files for pid in observed_starts[:3]), "Supervisor did not clear old volume contents after enforcement."
            assert f"run_{observed_starts[3]}.bin" in observed_files, "Supervisor did not restart the service after the third enforcement."
        finally:
            if proc is not None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            stop_existing_processes()
            shutil.copy2(os.path.join(backup, "service"), SERVICE)
            if os.path.exists(LOG):
                os.remove(LOG)
            if log_existed:
                shutil.copy2(os.path.join(backup, "log"), LOG)
            shutil.rmtree(VOLUME, ignore_errors=True)
            if volume_existed:
                shutil.copytree(os.path.join(backup, "volume"), VOLUME)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
