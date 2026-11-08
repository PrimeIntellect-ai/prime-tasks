#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import configparser
import secrets


def test_symlink_created():
    """Verify that the symlink settings.ini points to smtp_production.ini."""
    link_path = '/home/user/sysapp/mail/settings.ini'
    target_path = '/home/user/sysconfig/smtp_production.ini'

    assert os.path.islink(link_path), f"{link_path} is not a symbolic link."
    assert os.readlink(link_path) == target_path, f"Symlink {link_path} does not point to {target_path}."


def test_config_updated():
    """Verify that smtp_production.ini has the updated bind_address and port."""
    config_path = '/home/user/sysconfig/smtp_production.ini'
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."

    config = configparser.ConfigParser()
    config.read(config_path)

    assert 'smtp' in config, "Section [smtp] is missing in smtp_production.ini."
    assert config['smtp'].get('bind_address') == '127.0.0.1', "bind_address in smtp_production.ini is not 127.0.0.1."
    assert config['smtp'].get('port') == '2525', "port in smtp_production.ini is not 2525."


def test_bashrc_updated():
    """Verify that .bashrc contains and actually exports the required variables."""
    bashrc_path = '/home/user/.bashrc'
    assert os.path.isfile(bashrc_path), f"{bashrc_path} is missing."

    with open(bashrc_path, 'r') as f:
        content = f.read()

    assert 'MAIL_SERVER_HOST=127.0.0.1' in content, "MAIL_SERVER_HOST=127.0.0.1 not found in .bashrc."
    assert 'MAIL_SERVER_PORT=2525' in content, "MAIL_SERVER_PORT=2525 not found in .bashrc."

    env = os.environ.copy()
    env.pop('MAIL_SERVER_HOST', None)
    env.pop('MAIL_SERVER_PORT', None)
    command = r'''
unset MAIL_SERVER_HOST MAIL_SERVER_PORT
source /home/user/.bashrc
python3 -c 'import os,sys; sys.exit(0 if os.environ.get("MAIL_SERVER_HOST") == "127.0.0.1" and os.environ.get("MAIL_SERVER_PORT") == "2525" else 1)'
'''
    result = subprocess.run(
        ['bash', '--noprofile', '--norc', '-c', command],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        ".bashrc does not export MAIL_SERVER_HOST and MAIL_SERVER_PORT with the required values. "
        f"stderr: {result.stderr}"
    )


def test_verify_script_functionality():
    """Exercise verify.py over generated matching, mismatching, and missing values."""
    script_path = '/home/user/sysapp/mail/verify.py'
    config_path = '/home/user/sysconfig/smtp_production.ini'
    log_path = '/home/user/sysapp/mail/validation.log'

    assert os.path.isfile(script_path), f"Python script {script_path} is missing."
    assert os.path.isfile(config_path), f"Configuration file {config_path} is missing."

    with open(config_path, 'rb') as f:
        original_config = f.read()

    random_host = f"192.0.2.{secrets.randbelow(200) + 1}"
    random_port = str(secrets.randbelow(30000) + 30000)
    absent = object()

    def run_case(config_text, host, port, expected):
        with open(config_path, 'w') as f:
            f.write(config_text)

        if os.path.exists(log_path):
            os.remove(log_path)

        env = os.environ.copy()
        env.pop('MAIL_SERVER_HOST', None)
        env.pop('MAIL_SERVER_PORT', None)
        if host is not absent:
            env['MAIL_SERVER_HOST'] = host
        if port is not absent:
            env['MAIL_SERVER_PORT'] = port

        result = subprocess.run(
            ['python3', script_path],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Script execution failed: {result.stderr}"
        assert os.path.isfile(log_path), f"Log file {log_path} was not created."
        with open(log_path, 'r') as f:
            log_content = f.read().strip()
        assert log_content == expected, f"Expected {expected!r}, got {log_content!r}"

    canonical = '[smtp]\nbind_address = 127.0.0.1\nport = 2525\n'
    generated = f'[smtp]\nbind_address = {random_host}\nport = {random_port}\n'

    try:
        # Required final-state matching case.
        run_case(canonical, '127.0.0.1', '2525', 'MATCH: 127.0.0.1:2525')

        # Every environment value must participate in the comparison.
        run_case(canonical, random_host, '2525', 'ERROR')
        run_case(canonical, '127.0.0.1', random_port, 'ERROR')
        run_case(canonical, random_host, random_port, 'ERROR')

        # Missing environment values must produce ERROR rather than crash or match.
        run_case(canonical, absent, '2525', 'ERROR')
        run_case(canonical, '127.0.0.1', absent, 'ERROR')
        run_case(canonical, absent, absent, 'ERROR')

        # Generated configuration values ensure the script reads and compares the INI.
        run_case(generated, '127.0.0.1', '2525', 'ERROR')
        run_case(generated, random_host, random_port, 'MATCH: 127.0.0.1:2525')
        run_case(f'[smtp]\nport = {random_port}\n', random_host, random_port, 'ERROR')
        run_case(f'[smtp]\nbind_address = {random_host}\n', random_host, random_port, 'ERROR')
        run_case('[other]\nvalue = x\n', random_host, random_port, 'ERROR')
    finally:
        with open(config_path, 'wb') as f:
            f.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
