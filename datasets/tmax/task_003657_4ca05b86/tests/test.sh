#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import html
import json
import os
import re
import subprocess
import sys
import time


def test_cwe_findings():
    path = '/home/user/cwe_findings.txt'
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read().upper()

    cwes_found = re.findall(r'CWE-\d+', content)
    assert 'CWE-78' in cwes_found, "CWE-78 (Command Injection) not found in cwe_findings.txt."
    assert 'CWE-79' in cwes_found, "CWE-79 (Cross-Site Scripting) not found in cwe_findings.txt."

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert sorted(lines) == ['CWE-78', 'CWE-79'], \
        "cwe_findings.txt must contain exactly CWE-78 and CWE-79, one per line."


def test_pwned_file_does_not_exist():
    path = '/home/user/pwned_file'
    assert not os.path.exists(path), "Command injection was not mitigated; pwned_file exists."


def test_report_html_escaped():
    path = '/home/user/report.html'
    assert os.path.exists(path), f"File {path} is missing. Did you run the script?"

    with open(path, 'r') as f:
        content = f.read()

    assert "&lt;script&gt;" in content, "XSS was not mitigated; <script> tag was not escaped in report.html."
    assert "<script>" not in content, "XSS was not mitigated; raw <script> tag found in report.html."


def test_log_analyzer_fixes():
    path = '/home/user/log_analyzer.py'
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"File {path} is not a regular Python file."

    with open(path, 'r') as f:
        content = f.read()

    assert "html.escape" in content, "html.escape is not used in log_analyzer.py."
    assert "timeout=2" in content.replace(" ", ""), "timeout=2 is not used in subprocess.run."

    # Check that shell=True is removed or changed to shell=False
    assert "shell=True" not in content.replace(" ", ""), "shell=True is still present in log_analyzer.py."

    tree = ast.parse(content, filename=path)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    escape_calls = [
        call for call in calls
        if isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Name)
        and call.func.value.id == 'html'
        and call.func.attr == 'escape'
    ]
    assert escape_calls, "html.escape must be called by the program, not merely mentioned."

    run_calls = [
        call for call in calls
        if isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Name)
        and call.func.value.id == 'subprocess'
        and call.func.attr == 'run'
    ]
    assert run_calls, "The analyzer must actively call subprocess.run."
    assert any(
        any(kw.arg == 'timeout' and isinstance(kw.value, ast.Constant) and kw.value.value == 2
            for kw in call.keywords)
        for call in run_calls
    ), "An active subprocess.run call must use the exact timeout=2 keyword."
    assert all(
        not any(kw.arg == 'shell' and isinstance(kw.value, ast.Constant) and kw.value.value is True
                for kw in call.keywords)
        for call in run_calls
    ), "An active subprocess.run call still enables a shell."


def test_analyzer_on_adversarial_logs():
    analyzer = '/home/user/log_analyzer.py'
    logs_path = '/home/user/traffic_logs.json'
    report_path = '/home/user/report.html'
    pwned_path = '/home/user/verifier_pwned'
    argv_log = '/tmp/verifier_nslookup_argv.jsonl'
    fake_bin = '/tmp/verifier-bin'
    fake_nslookup = os.path.join(fake_bin, 'nslookup')

    with open(logs_path, 'rb') as f:
        original_logs = f.read()
    original_report = None
    if os.path.exists(report_path):
        with open(report_path, 'rb') as f:
            original_report = f.read()

    adversarial_logs = [
        {
            'ip': '127.0.0.1; touch /home/user/verifier_pwned',
            'url': '<img src=x onerror="alert(1)"> & unsafe'
        },
        {
            'ip': '<b>1.2.3.4 & "quoted"</b>',
            'url': '</li><script>alert("x")</script>'
        },
        {
            'ip': 'VERIFIER_TIMEOUT',
            'url': "'timeout URL'"
        }
    ]

    os.makedirs(fake_bin, exist_ok=True)
    with open(fake_nslookup, 'w') as f:
        f.write("""#!/usr/bin/python3
import json
import os
import sys
import time
with open(os.environ['VERIFIER_ARGV_LOG'], 'a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1:] == ['VERIFIER_TIMEOUT']:
    time.sleep(10)
sys.exit(0)
""")
    os.chmod(fake_nslookup, 0o755)

    if os.path.exists(argv_log):
        os.remove(argv_log)
    if os.path.exists(pwned_path):
        os.remove(pwned_path)

    try:
        with open(logs_path, 'w') as f:
            json.dump(adversarial_logs, f)

        env = os.environ.copy()
        env['PATH'] = fake_bin + os.pathsep + env.get('PATH', '')
        env['VERIFIER_ARGV_LOG'] = argv_log

        started = time.monotonic()
        result = subprocess.run(
            [sys.executable, analyzer],
            env=env,
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=6
        )
        elapsed = time.monotonic() - started

        assert result.returncode == 0, \
            f"log_analyzer.py failed on adversarial input: {result.stderr}"
        assert elapsed < 3.5, \
            f"DNS timeout was not enforced near 2 seconds (analyzer took {elapsed:.2f}s)."
        assert not os.path.exists(pwned_path), \
            "Command injection executed a touch command from the logged IP."

        assert os.path.exists(argv_log), "The analyzer did not execute the nslookup command."
        with open(argv_log, 'r') as f:
            observed_argv = [json.loads(line) for line in f if line.strip()]
        expected_argv = [[entry['ip']] for entry in adversarial_logs]
        assert observed_argv == expected_argv, \
            f"nslookup must receive each complete IP as one literal argument; got {observed_argv!r}."

        expected_statuses = ['Success', 'Success', 'Error']
        expected_report = '<html><body><h1>Traffic Report</h1><ul>\n'
        for entry, status in zip(adversarial_logs, expected_statuses):
            expected_report += (
                f"<li>IP: {html.escape(entry['ip'])} (Lookup: {status}) - "
                f"URL: {html.escape(entry['url'])}</li>\n"
            )
        expected_report += '</ul></body></html>'

        assert os.path.exists(report_path), "The executed analyzer did not generate report.html."
        with open(report_path, 'r') as f:
            actual_report = f.read()
        assert actual_report == expected_report, \
            "The analyzer did not preserve the report structure while escaping both IP and URL fields."
    finally:
        with open(logs_path, 'wb') as f:
            f.write(original_logs)
        if original_report is None:
            if os.path.exists(report_path):
                os.remove(report_path)
        else:
            with open(report_path, 'wb') as f:
                f.write(original_report)
        if os.path.exists(pwned_path):
            os.remove(pwned_path)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
