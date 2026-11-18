#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import sys
from pathlib import Path

SCRIPT = Path('/home/user/analyze_hardening.py')
REPORT = Path('/home/user/hardening_report.txt')
AUDIT_DIR = Path('/home/user/sys_audit')
FIXTURE_NAMES = ('etc_passwd', 'postfix_main.cf', 'iptables_save.txt', 'ping_results.txt')


def compute_expected():
    expected_uids = []
    passwd_path = AUDIT_DIR / 'etc_passwd'
    if passwd_path.is_file():
        with passwd_path.open('r') as f:
            for line in f:
                parts = line.strip().split(':')
                if len(parts) > 2 and parts[2] == '0' and parts[0] != 'root':
                    expected_uids.append(parts[0])
    expected_line1 = ','.join(expected_uids)

    expected_line2 = ''
    postfix_path = AUDIT_DIR / 'postfix_main.cf'
    if postfix_path.is_file():
        with postfix_path.open('r') as f:
            for line in f:
                if line.startswith('mynetworks') and '=' in line:
                    expected_line2 = line.split('=', 1)[1].strip()
                    break

    expected_line3 = ''
    iptables_path = AUDIT_DIR / 'iptables_save.txt'
    if iptables_path.is_file():
        with iptables_path.open('r') as f:
            for line in f:
                if 'ACCEPT' in line and '--dport' in line:
                    parts = line.split()
                    if '--dport' in parts:
                        idx = parts.index('--dport')
                        try:
                            port = int(parts[idx + 1])
                            if port > 1024:
                                expected_line3 = str(port)
                                break
                        except (ValueError, IndexError):
                            pass

    expected_line4_count = 0
    ping_path = AUDIT_DIR / 'ping_results.txt'
    if ping_path.is_file():
        with ping_path.open('r') as f:
            for line in f:
                if '0% packet loss' in line:
                    expected_line4_count += 1

    return [expected_line1, expected_line2, expected_line3, str(expected_line4_count)]


def run_script_and_check(expected):
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        [str(SCRIPT)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'Script exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert REPORT.is_file(), 'The script did not create /home/user/hardening_report.txt.'
    with REPORT.open('r') as f:
        lines = [line.strip('\n') for line in f.readlines()]
    assert len(lines) == 4, f'Expected exactly 4 lines, found {len(lines)}.'
    assert lines == expected, f'Generated report was {lines!r}; expected {expected!r}.'


def test_analyzer_exists_is_executable_and_parses_inputs():
    assert SCRIPT.is_file(), f'The required script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'The required script {SCRIPT} is not executable.'

    compiled = subprocess.run(
        [sys.executable, '-m', 'py_compile', str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert compiled.returncode == 0, f'The analyzer is not valid Python: {compiled.stderr}'

    originals = {name: (AUDIT_DIR / name).read_bytes() for name in FIXTURE_NAMES}
    variants = [
        {
            'etc_passwd': 'root:x:0:0:root:/root:/bin/bash\nauditor:x:0:5::/tmp:/bin/sh\nnormal:x:1002:1002::/home/normal:/bin/bash\nrescue:x:0:9::/srv:/bin/bash\n',
            'postfix_main.cf': 'relayhost = mail.example\nmynetworks = 10.20.0.0/16, [::1]/128\nmyhostname = test-one\n',
            'iptables_save.txt': '*filter\n-A INPUT -p tcp --dport 443 -j ACCEPT\n-A INPUT -p tcp --dport 6123 -j ACCEPT\n-A INPUT -p tcp --dport 9000 -j DROP\nCOMMIT\n',
            'ping_results.txt': 'PING first (1.1.1.1)\n--- first ping statistics ---\n2 packets transmitted, 2 received, 0% packet loss\n\nPING second (2.2.2.2)\n--- second ping statistics ---\n2 packets transmitted, 1 received, 50% packet loss\n',
        },
        {
            'etc_passwd': 'service:x:33:33::/:/usr/sbin/nologin\nroot:x:0:0:root:/root:/bin/bash\nemergency:x:0:0::/opt:/bin/sh\n',
            'postfix_main.cf': 'mynetworks = 192.0.2.4/32\ncompatibility_level = 3.6\n',
            'iptables_save.txt': '*filter\n-A INPUT -p udp --dport 53 -j ACCEPT\n-A INPUT -p tcp --dport 2345 -j ACCEPT\nCOMMIT\n',
            'ping_results.txt': 'PING a\n--- a ping statistics ---\n1 packets transmitted, 1 received, 0% packet loss\n\nPING b\n--- b ping statistics ---\n1 packets transmitted, 1 received, 0% packet loss\n\nPING c\n--- c ping statistics ---\n4 packets transmitted, 1 received, 75% packet loss\n',
        },
    ]

    try:
        for variant in variants:
            for name, contents in variant.items():
                (AUDIT_DIR / name).write_text(contents)
            expected = compute_expected()
            run_script_and_check(expected)
    finally:
        for name, contents in originals.items():
            (AUDIT_DIR / name).write_bytes(contents)

    # Leave a freshly generated report from the original fixtures for the
    # original final-state assertions below.
    run_script_and_check(compute_expected())


def test_hardening_report_exists():
    report_path = '/home/user/hardening_report.txt'
    assert os.path.isfile(report_path), f'The report file {report_path} was not created.'


def test_hardening_report_contents():
    report_path = '/home/user/hardening_report.txt'
    assert os.path.isfile(report_path), 'The report file is missing.'

    # Compute expected Line 1
    expected_uids = []
    passwd_path = '/home/user/sys_audit/etc_passwd'
    if os.path.isfile(passwd_path):
        with open(passwd_path, 'r') as f:
            for line in f:
                parts = line.strip().split(':')
                if len(parts) > 2 and parts[2] == '0' and parts[0] != 'root':
                    expected_uids.append(parts[0])
    expected_line1 = ','.join(expected_uids)

    # Compute expected Line 2
    expected_line2 = ''
    postfix_path = '/home/user/sys_audit/postfix_main.cf'
    if os.path.isfile(postfix_path):
        with open(postfix_path, 'r') as f:
            for line in f:
                if line.startswith('mynetworks') and '=' in line:
                    expected_line2 = line.split('=', 1)[1].strip()
                    break

    # Compute expected Line 3
    expected_line3 = ''
    iptables_path = '/home/user/sys_audit/iptables_save.txt'
    if os.path.isfile(iptables_path):
        with open(iptables_path, 'r') as f:
            for line in f:
                if 'ACCEPT' in line and '--dport' in line:
                    parts = line.split()
                    if '--dport' in parts:
                        idx = parts.index('--dport')
                        try:
                            port = int(parts[idx+1])
                            if port > 1024:
                                expected_line3 = str(port)
                                break
                        except ValueError:
                            pass

    # Compute expected Line 4
    expected_line4_count = 0
    ping_path = '/home/user/sys_audit/ping_results.txt'
    if os.path.isfile(ping_path):
        with open(ping_path, 'r') as f:
            for line in f:
                if '0% packet loss' in line:
                    expected_line4_count += 1
    expected_line4 = str(expected_line4_count)

    # Read the actual report
    with open(report_path, 'r') as f:
        lines = [line.strip('\n') for line in f.readlines()]

    assert len(lines) == 4, f'Expected exactly 4 lines in the report, found {len(lines)}.'

    assert lines[0] == expected_line1, f"Line 1 is incorrect. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 is incorrect. Expected '{expected_line2}', got '{lines[1]}'."
    assert lines[2] == expected_line3, f"Line 3 is incorrect. Expected '{expected_line3}', got '{lines[2]}'."
    assert lines[3] == expected_line4, f"Line 4 is incorrect. Expected '{expected_line4}', got '{lines[3]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
