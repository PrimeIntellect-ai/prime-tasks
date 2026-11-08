#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_apply_fw_script():
    script_path = "/home/user/apply_fw.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "#!/bin/bash",
        "iptables -I INPUT -p tcp --dport 4444 -j DROP",
        "iptables -I INPUT -p tcp --dport 8080 -j DROP",
        "iptables -I INPUT -p tcp --dport 31337 -j DROP",
    ]
    assert content == expected_lines, f"{script_path} content does not match expected output."


def test_bashrc_configured():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "export SEC_HARDENED=true" in content, \
        f"{bashrc_path} does not contain 'export SEC_HARDENED=true'."


def test_quarantine_directory_and_files():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Directory {quarantine_dir} does not exist."

    expected_files = {
        "server.conf": b"ALLOW_ANON=true\n",
        "api.conf": b"User config ALLOW_ANON enabled\n",
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(quarantine_dir, filename)
        assert os.path.isfile(filepath), f"Quarantined file {filepath} does not exist."

        perms = stat.S_IMODE(os.stat(filepath).st_mode)
        assert perms == 0o000, \
            f"Permissions for {filepath} are not 000 (found {oct(perms)})."

        with open(filepath, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, \
            f"Quarantined file {filepath} does not preserve the original content."


def test_original_files_removed():
    removed_files = [
        "/home/user/app_data/sub1/server.conf",
        "/home/user/app_data/sub2/api.conf",
    ]
    for filepath in removed_files:
        assert not os.path.exists(filepath), f"Vulnerable file {filepath} was not moved/removed."


def test_all_application_conf_files_are_clean():
    app_data = "/home/user/app_data"
    for root, _, files in os.walk(app_data):
        for filename in files:
            if not filename.endswith(".conf"):
                continue
            filepath = os.path.join(root, filename)
            assert os.path.isfile(filepath), f"Configuration path {filepath} is not a regular file."
            with open(filepath, "rb") as f:
                content = f.read()
            assert b"ALLOW_ANON" not in content, \
                f"Vulnerable configuration {filepath} remains under {app_data}."


def test_safe_files_remain():
    safe_files = [
        "/home/user/app_data/safe.txt",
        "/home/user/app_data/sub1/secure.conf",
    ]
    for filepath in safe_files:
        assert os.path.isfile(filepath), f"Safe file {filepath} is missing. It should not have been moved."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
