#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_deploy_script_exists_and_executable():
    script_path = "/home/user/deploy_update.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Deployment script {script_path} is not executable."


def test_fstab_updated_idempotently():
    fstab_path = "/home/user/mock_etc/fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        lines = f.readlines()

    target_line = "UUID=99A1-B2C3 /home/user/app_backup ext4 defaults 0 2"
    count = sum(1 for line in lines if target_line in line)
    exact_count = sum(1 for line in lines if line.rstrip("\r\n") == target_line)

    assert count == 1, f"Expected exactly 1 instance of '{target_line}' in {fstab_path}, found {count}."
    assert exact_count == 1, f"Expected exactly one complete line '{target_line}' in {fstab_path}, found {exact_count}."


def test_firewall_rules_updated_idempotently():
    firewall_path = "/home/user/mock_etc/firewall.rules"
    assert os.path.isfile(firewall_path), f"File {firewall_path} does not exist."

    with open(firewall_path, "r") as f:
        lines = f.readlines()

    target_line = "FORWARD TCP 8080 -> 9090"
    count = sum(1 for line in lines if target_line in line)
    exact_count = sum(1 for line in lines if line.rstrip("\r\n") == target_line)

    assert count == 1, f"Expected exactly 1 instance of '{target_line}' in {firewall_path}, found {count}."
    assert exact_count == 1, f"Expected exactly one complete line '{target_line}' in {firewall_path}, found {exact_count}."


def test_app_data_directory_permissions():
    app_data_path = "/home/user/app_data"
    assert os.path.isdir(app_data_path), f"Directory {app_data_path} does not exist."

    st = os.stat(app_data_path)
    permissions = stat.S_IMODE(st.st_mode)

    assert permissions == 0o700, f"Expected permissions 0o700 for {app_data_path}, got {oct(permissions)}."


def test_deployment_log_contents():
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    expected_lines = [
        "[SUCCESS] Mount configured",
        "[SUCCESS] Firewall updated",
        "[SUCCESS] Permissions set"
    ]

    for line in expected_lines:
        assert line in content, f"Expected log line '{line}' not found in {log_path}."

    assert content.splitlines() == expected_lines, \
        f"Expected exactly the three required log lines in order, got: {content.splitlines()!r}"
TEST_EOF

# Discard any fabricated final state and restore the supplied starting state.
rm -rf /home/user/app_data /home/user/deploy.log || status=1
mkdir -p /home/user/mock_etc || status=1
cat << 'EOF' > /home/user/mock_etc/fstab
# /etc/fstab: static file system information.
UUID=1234-5678 / ext4 errors=remount-ro 0 1
EOF
if [ $? -ne 0 ]; then status=1; fi
cat << 'EOF' > /home/user/mock_etc/firewall.rules
# Custom firewall rules
ALLOW TCP 22
ALLOW TCP 80
EOF
if [ $? -ne 0 ]; then status=1; fi
chown user:user /home/user/mock_etc /home/user/mock_etc/fstab /home/user/mock_etc/firewall.rules || status=1
chmod 755 /home/user /home/user/mock_etc || status=1
chmod 666 /home/user/mock_etc/fstab /home/user/mock_etc/firewall.rules || status=1

# Execute and validate once from a clean state.
if [ "$status" -eq 0 ]; then
    runuser -u user -- /home/user/deploy_update.sh || status=1
fi
if [ "$status" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

# Execute and validate a second time to exercise idempotency.
if [ "$status" -eq 0 ]; then
    runuser -u user -- /home/user/deploy_update.sh || status=1
fi
if [ "$status" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
