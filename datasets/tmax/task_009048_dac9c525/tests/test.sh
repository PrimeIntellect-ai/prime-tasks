#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shlex
import shutil
import subprocess
import uuid


def read_text(path):
    with open(path, "r") as f:
        return f.read()


def validate_port_forward(path):
    assert os.path.isfile(path), f"File {path} is missing."

    content = read_text(path).strip()

    # Preserve the original token assertions.
    assert "iptables" in content, "iptables command missing 'iptables'"
    assert "-t nat" in content, "iptables command missing '-t nat'"
    assert "PREROUTING" in content, "iptables command missing 'PREROUTING'"
    assert "-i eth0" in content, "iptables command missing '-i eth0'"
    assert "-p tcp" in content, "iptables command missing '-p tcp'"
    assert "80" in content, "iptables command missing port '80'"
    assert "REDIRECT" in content, "iptables command missing 'REDIRECT'"
    assert "8080" in content, "iptables command missing port '8080'"

    lines = [line for line in content.split("\n") if line.strip() and not line.startswith("#")]
    assert len(lines) == 1, f"File {path} should contain exactly one iptables command line."
    assert len(content.splitlines()) == 1, f"File {path} must contain only the command."

    tokens = shlex.split(content)
    assert tokens and tokens[0] == "iptables", "Command must invoke iptables directly."

    aliases = {
        "-t": "table", "--table": "table",
        "-A": "chain", "--append": "chain",
        "-i": "interface", "--in-interface": "interface",
        "-p": "protocol", "--protocol": "protocol",
        "--dport": "dport", "--destination-port": "dport",
        "-j": "target", "--jump": "target",
        "--to-port": "to_port", "--to-ports": "to_port",
    }
    values = {}
    i = 1
    while i < len(tokens):
        option = tokens[i]
        assert option in aliases, f"Unexpected token in iptables command: {option}"
        assert i + 1 < len(tokens), f"Missing value for {option}"
        key = aliases[option]
        assert key not in values, f"Duplicate iptables option for {key}"
        values[key] = tokens[i + 1]
        i += 2

    assert values == {
        "table": "nat",
        "chain": "PREROUTING",
        "interface": "eth0",
        "protocol": "tcp",
        "dport": "80",
        "target": "REDIRECT",
        "to_port": "8080",
    }, f"Incorrect iptables rule semantics: {values}"

    translator = shutil.which("iptables-translate")
    assert translator is not None, "iptables-translate is unavailable"
    parsed = subprocess.run(
        [translator] + tokens[1:],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert parsed.returncode == 0, f"Invalid iptables command: {parsed.stderr or parsed.stdout}"


def test_submission_and_dynamic_behavior():
    script_path = "/home/user/fix_app.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable."

    # Preserve all checks against the requested initial final state.
    conf_path = "/home/user/app/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config {conf_path} is missing."
    content = read_text(conf_path)
    expected_directive = "proxy_pass http://unix:/home/user/app/run/gunicorn.sock;"
    assert expected_directive in content, f"Nginx config does not contain the corrected proxy_pass directive: {expected_directive}"
    assert content.count("proxy_pass") == 1, "Nginx config contains multiple proxy_pass directives, suggesting the script is not idempotent."

    output_path = "/home/user/failed_sockets.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."
    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "/home/user/app/gunicorn.sock",
        "/home/user/app/tmp/gunicorn.sock",
    ]
    assert lines == expected_lines, f"Contents of {output_path} are incorrect. Expected {expected_lines}, got {lines}."

    port_path = "/home/user/port_forward.sh"
    validate_port_forward(port_path)

    # Replace the fixtures with verifier-generated values, then require the
    # submitted script itself to discover and process them.
    marker = uuid.uuid4().hex
    app_root = "/home/user/app"
    for root, dirs, files in os.walk(app_root):
        if "gunicorn.sock" in files:
            os.unlink(os.path.join(root, "gunicorn.sock"))

    socket_dir = os.path.join(app_root, "runtime_" + marker, "nested")
    os.makedirs(socket_dir, exist_ok=True)
    actual_socket = os.path.join(socket_dir, "gunicorn.sock")
    open(actual_socket, "a").close()

    with open(conf_path, "w") as f:
        f.write("""server {
    listen 8080;
    server_name localhost;

    location / {
        proxy_pass http://unix:/definitely/wrong/gunicorn.sock;
        proxy_set_header Host $host;
    }
}
""")

    failed = sorted([
        f"/stale/{marker}/alpha.sock",
        f"/stale/{marker}/middle.sock",
        f"/stale/{marker}/zeta.sock",
    ])
    log_path = os.path.join(app_root, "logs", "error.log")
    with open(log_path, "w") as f:
        f.write(f"2026/01/01 00:00:01 [error] 1#0: *1 connect() to unix:{failed[2]} failed (2: No such file or directory) while connecting to upstream\n")
        f.write(f"2026/01/01 00:00:02 [info] 1#0: harmless unix:/ignore/{marker}.sock message\n")
        f.write(f"2026/01/01 00:00:03 [error] 1#0: *2 connect() to unix:{failed[0]} failed (111: Connection refused) while connecting to upstream\n")
        f.write(f"2026/01/01 00:00:04 [error] 1#0: *3 connect() to unix:{failed[1]} failed (2: No such file or directory) while connecting to upstream\n")
        f.write(f"2026/01/01 00:00:05 [error] 1#0: *4 connect() to unix:{failed[0]} failed (2: No such file or directory) while connecting to upstream\n")

    for generated in (output_path, port_path):
        if os.path.lexists(generated):
            os.unlink(generated)

    first_run = subprocess.run(
        [script_path], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert first_run.returncode == 0, f"fix_app.sh failed: {first_run.stderr}"

    dynamic_conf = read_text(conf_path)
    dynamic_directive = f"proxy_pass http://unix:{actual_socket};"
    assert dynamic_directive in dynamic_conf, f"Script did not discover the actual socket {actual_socket}"
    assert dynamic_conf.count("proxy_pass") == 1, "Script created duplicate proxy_pass directives."

    assert os.path.isfile(output_path), f"Output file {output_path} is missing after execution."
    with open(output_path, "r") as f:
        dynamic_lines = [line.strip() for line in f if line.strip()]
    assert dynamic_lines == failed, f"Script did not derive sorted unique failed sockets: {dynamic_lines}"
    validate_port_forward(port_path)

    first_state = {
        conf_path: read_text(conf_path),
        output_path: read_text(output_path),
        port_path: read_text(port_path),
    }
    second_run = subprocess.run(
        [script_path], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert second_run.returncode == 0, f"Second fix_app.sh execution failed: {second_run.stderr}"
    second_state = {path: read_text(path) for path in first_state}
    assert second_state == first_state, "Running fix_app.sh twice changes or corrupts its outputs."
    assert second_state[conf_path].count("proxy_pass") == 1, "Repeated execution duplicated proxy_pass."


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
