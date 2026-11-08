#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess


def test_analyzer_executable_exists():
    """Verify that the compiled C program exists and is executable."""
    executable_path = '/home/user/analyzer'
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Executable {executable_path} is not a compiled ELF binary."


def test_config_backup_exists_and_matches():
    """Verify that config.ini.bak exists and matches the original config.ini."""
    original_path = '/home/user/net_data/config.ini'
    backup_path = '/home/user/config.ini.bak'

    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."
    assert os.path.isfile(original_path), f"Original file {original_path} is missing."

    with open(original_path, 'r') as f_orig, open(backup_path, 'r') as f_bak:
        original_content = f_orig.read()
        backup_content = f_bak.read()

    assert backup_content == original_content, "The backup file contents do not match the original config.ini."


def test_resolution_log_exists_and_content():
    """Verify that resolution.log exists and contains the correct extracted information."""
    log_path = '/home/user/resolution.log'
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_content = "MountPoint: /home/user/net_data\nForwardedPort: 8088"
    assert content == expected_content, f"The contents of {log_path} are incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_source_compiles_and_analyzer_parses_dynamic_inputs(tmp_path):
    source_path = '/home/user/analyzer.c'
    assert os.path.isfile(source_path), f"C source {source_path} is missing."

    rebuilt = tmp_path / 'analyzer-rebuilt'
    compile_result = subprocess.run(
        ['gcc', source_path, '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"analyzer.c does not compile:\n{compile_result.stderr}"

    executables = ['/home/user/analyzer', str(rebuilt)]
    for executable in executables:
        token = secrets.token_hex(8)
        mount_point = f'/home/user/net_dynamic_{token}'
        forwarded_port = random.SystemRandom().randint(12000, 59000)
        config_content = (
            '[Daemon]\n'
            f'ListenPort={random.SystemRandom().randint(1, 65535)}\n'
            f'LogLevel=TEST_{token}\n'
            f'EnableCache={secrets.choice(["true", "false"])}\n'
        )

        os.makedirs(mount_point, exist_ok=True)
        config_path = os.path.join(mount_point, 'config.ini')
        with open(config_path, 'w') as f:
            f.write(config_content)

        with open('/home/user/fstab.mock', 'w') as f:
            f.write('UUID=ROOT-FS / ext4 defaults 1 1\n')
            f.write('UUID=OTHER-FS /mnt/other ext4 defaults 0 2\n')
            f.write(f'UUID=NET-CONFIG-FS {mount_point} ext4 defaults,user 0 0\n')
            f.write('UUID=SWAP none swap sw 0 0\n')

        with open('/home/user/iptables.dump', 'w') as f:
            f.write('*nat\n')
            f.write(':PREROUTING ACCEPT [0:0]\n')
            f.write(':INPUT ACCEPT [0:0]\n')
            f.write(':OUTPUT ACCEPT [0:0]\n')
            f.write(':POSTROUTING ACCEPT [0:0]\n')
            f.write('-A PREROUTING -i eth0 -p tcp -m tcp --dport 443 -j REDIRECT --to-ports 8443\n')
            f.write(f'-A PREROUTING -i eth0 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports {forwarded_port}\n')
            f.write('-A PREROUTING -i eth0 -p tcp -m tcp --dport 8080 -j REDIRECT --to-ports 8089\n')
            f.write('COMMIT\n')

        for output in ('/home/user/config.ini.bak', '/home/user/resolution.log'):
            if os.path.exists(output):
                os.remove(output)

        run_result = subprocess.run(
            [executable],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert run_result.returncode == 0, (
            f"{executable} failed on dynamic inputs with exit code {run_result.returncode}:\n"
            f"{run_result.stderr}"
        )

        assert os.path.isfile('/home/user/config.ini.bak'), "Analyzer did not create config.ini.bak."
        with open('/home/user/config.ini.bak', 'r') as f:
            assert f.read() == config_content, "Analyzer backed up the wrong config.ini contents."

        assert os.path.isfile('/home/user/resolution.log'), "Analyzer did not create resolution.log."
        with open('/home/user/resolution.log', 'r') as f:
            actual_log = f.read().strip()
        expected_log = f'MountPoint: {mount_point}\nForwardedPort: {forwarded_port}'
        assert actual_log == expected_log, (
            f"Analyzer did not dynamically parse the mock files. Expected:\n{expected_log}\nGot:\n{actual_log}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
