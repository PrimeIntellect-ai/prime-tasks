#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import secrets
import shutil
import stat
import subprocess


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_00_original_artifacts():
    log_path = "/home/user/privesc.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Privilege escalation auditing failed."
    lines = nonempty_lines(log_path)
    assert set(lines) == {"developer", "ci_runner"}, f"{log_path} does not contain the correct non-admin privileged roles. Found: {lines}"

    log_path = "/home/user/injection.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Injection vulnerability analysis failed."
    lines = nonempty_lines(log_path)
    expected_path = "/home/user/vulnerable_app/db.go"
    assert expected_path in lines, f"{log_path} does not contain the expected file path {expected_path}."
    assert collections.Counter(lines) == collections.Counter([expected_path]), f"{log_path} contains unexpected or duplicate entries: {lines}"

    log_path = "/home/user/xss.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. XSS vulnerability analysis failed."
    lines = nonempty_lines(log_path)
    expected_path = "/home/user/vulnerable_app/views/index.html"
    assert expected_path in lines, f"{log_path} does not contain the expected file path {expected_path}."
    assert collections.Counter(lines) == collections.Counter([expected_path]), f"{log_path} contains unexpected or duplicate entries: {lines}"

    clean_path = "/home/user/secrets_clean.txt"
    assert os.path.isfile(clean_path), f"File {clean_path} does not exist. Sensitive data redaction failed."
    with open(clean_path, "r") as f:
        content = f.read()
    assert "AKIAIOSFODNN7EXAMPLE" not in content, "First AWS access key was not redacted."
    assert "AKIA1234567890ABCDEF" not in content, "Second AWS access key was not redacted."
    assert "AWS_ACCESS_KEY_ID=[REDACTED]" in content, "First AWS access key was not correctly replaced with [REDACTED]."
    assert "SomeOtherKey=[REDACTED]" in content, "Second AWS access key was not correctly replaced with [REDACTED]."
    assert "DatabaseURL=postgres://user:pass@localhost:5432/db" in content, "Non-sensitive data was improperly modified."
    assert "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" in content, "AWS secret key was improperly modified."

    script_path = "/home/user/block.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist. Firewall script generation failed."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} does not have executable permissions set."
    assert stat.S_IMODE(st.st_mode) == 0o755, f"{script_path} must have exact mode 0755, found {oct(stat.S_IMODE(st.st_mode))}."
    lines = nonempty_lines(script_path)
    assert len(lines) > 0, f"{script_path} is empty."
    assert lines[0] == "#!/bin/bash", f"{script_path} does not start with #!/bin/bash."
    expected_ips = ["192.168.1.50", "10.0.0.5", "203.0.113.42"]
    for ip in expected_ips:
        expected_rule = f"iptables -A INPUT -s {ip} -j DROP"
        assert expected_rule in lines, f"Missing expected iptables rule for IP {ip} in {script_path}."
    expected_lines = ["#!/bin/bash"] + [f"iptables -A INPUT -s {ip} -j DROP" for ip in expected_ips]
    assert collections.Counter(lines) == collections.Counter(expected_lines), f"{script_path} contains unexpected or duplicate rules: {lines}"


def test_10_program_compiles_and_handles_fresh_fixture():
    source = "/home/user/sec-audit.go"
    assert os.path.isfile(source), f"Required Go source file {source} does not exist."

    binary = f"/tmp/sec-audit-{secrets.token_hex(8)}"
    build = subprocess.run(
        ["go", "build", "-o", binary, source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"{source} does not compile:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Go build did not produce an executable."

    app = "/home/user/vulnerable_app"
    backup = f"/tmp/vulnerable_app_backup_{secrets.token_hex(8)}"
    shutil.move(app, backup)
    os.makedirs(os.path.join(app, "nested", "deeper"))

    token = secrets.token_hex(10)
    privileged = [f"ops_{token}", f"runner_{token}"]
    rbac = {
        "roles": [
            {"name": f"guest_{token}", "can_sudo": False},
            {"name": privileged[0], "can_sudo": True},
            {"name": "admin", "can_sudo": True},
            {"name": privileged[1], "can_sudo": True},
        ]
    }
    with open(os.path.join(app, "rbac.json"), "w") as f:
        json.dump(rbac, f)

    injection_paths = [
        os.path.join(app, f"query_{token}.go"),
        os.path.join(app, "nested", f"report_{token}.go"),
    ]
    with open(injection_paths[0], "w") as f:
        f.write('package sample\n// fmt.Sprintf("SELECT dynamically detected")\n')
    with open(injection_paths[1], "w") as f:
        f.write('package sample\nvar q = fmt.Sprintf("SELECT value")\n')
    with open(os.path.join(app, "safe.go"), "w") as f:
        f.write('package sample\nvar q = "SELECT but not Sprintf"\n')
    with open(os.path.join(app, "ignored.go.txt"), "w") as f:
        f.write('fmt.Sprintf("SELECT wrong extension")\n')

    xss_paths = [
        os.path.join(app, f"page_{token}.html"),
        os.path.join(app, "nested", "deeper", f"panel_{token}.html"),
    ]
    with open(xss_paths[0], "w") as f:
        f.write("<div>{{.DynamicUser}}</div>\n")
    with open(xss_paths[1], "w") as f:
        f.write("<span>{{.DynamicValue}}</span>\n")
    with open(os.path.join(app, "safe.html"), "w") as f:
        f.write("<p>{{ .SpacedValue }}</p>\n")

    key1 = "AKIA" + secrets.token_hex(12).upper()
    key2 = "AKIA" + secrets.token_hex(9).upper() + ",suffix"
    secret_input = (
        f"DatabaseURL=postgres://dynamic-{token}/db\n"
        f"AWS_ACCESS_KEY_ID={key1}\n"
        f"Embedded={key2}\n"
        f"AWS_SECRET_ACCESS_KEY=unchanged-{token}\n"
    )
    with open(os.path.join(app, "secrets.txt"), "w") as f:
        f.write(secret_input)
    expected_clean = re.sub(r"AKIA\S*", "[REDACTED]", secret_input)

    ips = [
        f"198.51.100.{secrets.randbelow(200) + 1}",
        f"203.0.113.{secrets.randbelow(200) + 1}",
        f"192.0.2.{secrets.randbelow(200) + 1}",
    ]
    with open(os.path.join(app, "threats.txt"), "w") as f:
        f.write("\n".join(ips) + "\n")

    outputs = [
        "/home/user/privesc.log",
        "/home/user/injection.log",
        "/home/user/xss.log",
        "/home/user/secrets_clean.txt",
        "/home/user/block.sh",
    ]
    for output in outputs:
        if os.path.lexists(output):
            os.remove(output)

    run = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert run.returncode == 0, f"Compiled audit program failed:\n{run.stdout}\n{run.stderr}"

    assert collections.Counter(nonempty_lines("/home/user/privesc.log")) == collections.Counter(privileged)
    assert collections.Counter(nonempty_lines("/home/user/injection.log")) == collections.Counter(injection_paths)
    assert collections.Counter(nonempty_lines("/home/user/xss.log")) == collections.Counter(xss_paths)

    with open("/home/user/secrets_clean.txt", "r") as f:
        assert f.read() == expected_clean, "Sanitized configuration does not exactly match the derived result."

    block_path = "/home/user/block.sh"
    assert os.path.isfile(block_path)
    assert stat.S_IMODE(os.stat(block_path).st_mode) == 0o755, "block.sh does not have exact mode 0755."
    expected_block = ["#!/bin/bash"] + [f"iptables -A INPUT -s {ip} -j DROP" for ip in ips]
    assert collections.Counter(nonempty_lines(block_path)) == collections.Counter(expected_block), "block.sh contains missing, duplicate, or fabricated entries."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
