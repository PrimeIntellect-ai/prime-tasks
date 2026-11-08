#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import stat
import subprocess

SSH_CONFIG_PATH = "/home/user/.ssh/config"
FSTAB_PATH = "/home/user/port_fstab"
PY_SCRIPT_PATH = "/home/user/tunnel_builder.py"
SH_SCRIPT_PATH = "/home/user/start_tunnels.sh"


def test_ssh_config_exists_and_permissions():
    """Verify .ssh/config exists and has correct permissions."""
    assert os.path.isfile(SSH_CONFIG_PATH), f"{SSH_CONFIG_PATH} is missing"
    st = os.stat(SSH_CONFIG_PATH)
    assert bool(st.st_mode & stat.S_IRUSR), f"{SSH_CONFIG_PATH} must be readable by user"
    assert stat.S_IMODE(st.st_mode) == 0o600, f"{SSH_CONFIG_PATH} must have permissions 0600"


def test_ssh_config_content():
    """Verify .ssh/config contains the correct jump hosts."""
    with open(SSH_CONFIG_PATH, 'r') as f:
        content = f.read().lower()

    # Preserve the original assertions.
    assert "host jump_web" in content, "Missing 'Host jump_web' in ssh config"
    assert "hostname ssh.web-infra.example.com" in content, "Missing correct HostName for jump_web"
    assert "user webops" in content, "Missing correct User for jump_web"
    assert "port 2222" in content, "Missing correct Port for jump_web"
    assert "host jump_db" in content, "Missing 'Host jump_db' in ssh config"
    assert "hostname ssh.data-infra.example.internal" in content, "Missing correct HostName for jump_db"
    assert "user dbadmin" in content, "Missing correct User for jump_db"

    # Parse Host blocks so unrelated substrings cannot satisfy the checks.
    blocks = []
    current = None
    with open(SSH_CONFIG_PATH, 'r') as f:
        for raw in f:
            stripped = raw.strip()
            if not stripped or stripped.startswith('#'):
                continue
            parts = stripped.split(None, 1)
            key = parts[0].lower()
            value = parts[1].strip() if len(parts) == 2 else ""
            if key == 'host':
                current = {'hosts': value.split(), 'directives': {}}
                blocks.append(current)
            elif current is not None:
                current['directives'].setdefault(key, []).append(value)

    expected = {
        'jump_web': {
            'hostname': 'ssh.web-infra.example.com',
            'user': 'webops',
            'port': '2222',
        },
        'jump_db': {
            'hostname': 'ssh.data-infra.example.internal',
            'user': 'dbadmin',
            'port': '22',
        },
    }
    for alias, directives in expected.items():
        matching = [b for b in blocks if b['hosts'] == [alias]]
        assert len(matching) == 1, f"Expected exactly one Host {alias} block"
        block = matching[0]['directives']
        for key, value in directives.items():
            assert block.get(key) == [value], f"Host {alias} must set {key} exactly to {value}"


def test_port_fstab_content():
    """Verify port_fstab contains the correct entries and a comment."""
    assert os.path.isfile(FSTAB_PATH), f"{FSTAB_PATH} is missing"
    with open(FSTAB_PATH, 'r') as f:
        lines = f.readlines()

    content = "".join(lines)
    assert "#" in content, "port_fstab must contain a comment line starting with #"

    # Preserve the original assertions.
    entry1_found = any("8080" in line and "10.1.1.50:80" in line and "jump_web" in line and "-N" in line and "-T" in line for line in lines)
    entry2_found = any("5432" in line and "192.168.100.10:5432" in line and "jump_db" in line and "-N" in line and "-f" in line for line in lines)
    assert entry1_found, "Missing or incorrect entry for port 8080 in port_fstab"
    assert entry2_found, "Missing or incorrect entry for port 5432 in port_fstab"

    assert lines and lines[0].lstrip().startswith('#'), "The top line of port_fstab must be a comment"
    entries = [line.split() for line in lines if line.strip() and not line.lstrip().startswith('#')]
    assert entries == [
        ['8080', '10.1.1.50:80', 'jump_web', '-N', '-T'],
        ['5432', '192.168.100.10:5432', 'jump_db', '-N', '-f'],
    ], "port_fstab must contain exactly the two requested entries in the requested format"


def run_builder(answers):
    return subprocess.run(
        ['python3', PY_SCRIPT_PATH],
        input=answers,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        cwd='/home/user',
    )


def read_generated_lines():
    assert os.path.isfile(SH_SCRIPT_PATH), f"{SH_SCRIPT_PATH} was not generated"
    with open(SH_SCRIPT_PATH, 'r') as f:
        return f.read().splitlines()


def test_tunnel_builder_script():
    """Execute the builder against unpredictable entries and exercise y/n behavior."""
    assert os.path.isfile(PY_SCRIPT_PATH), f"{PY_SCRIPT_PATH} is missing"

    with open(PY_SCRIPT_PATH, 'r') as f:
        tree = ast.parse(f.read(), filename=PY_SCRIPT_PATH)
    assert any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'input'
        for node in ast.walk(tree)
    ), "tunnel_builder.py must prompt using input()"

    with open(FSTAB_PATH, 'rb') as f:
        original_fstab = f.read()
    original_mode = stat.S_IMODE(os.stat(FSTAB_PATH).st_mode)

    token = secrets.token_hex(6)
    port1 = str(20000 + secrets.randbelow(10000))
    port2 = str(40000 + secrets.randbelow(10000))
    target1 = f"app-{token}.internal:8443"
    target2 = f"db-{token}.internal:6432"
    alias1 = f"jump_app_{token}"
    alias2 = f"jump_data_{token}"
    cmd1 = f"ssh -L {port1}:{target1} -N -T {alias1}"
    cmd2 = f"ssh -L {port2}:{target2} -N -f {alias2}"
    prompt1 = f"Enable tunnel to {target1} on local port {port1}? (y/n): "
    prompt2 = f"Enable tunnel to {target2} on local port {port2}? (y/n): "

    dynamic_fstab = (
        f"# dynamically supplied verification entries\n\n"
        f"{port1} {target1} {alias1} -N -T\n"
        f"# this comment must be skipped\n"
        f"{port2} {target2} {alias2} -N -f\n"
    )

    try:
        with open(FSTAB_PATH, 'w') as f:
            f.write(dynamic_fstab)

        # A stale file must be overwritten, and only the y-selected entry emitted.
        with open(SH_SCRIPT_PATH, 'w') as f:
            f.write("STALE CONTENT THAT MUST DISAPPEAR\n")
        os.chmod(SH_SCRIPT_PATH, 0o644)
        first = run_builder("n\ny\n")
        assert first.returncode == 0, f"builder failed: {first.stderr}"
        assert prompt1 in first.stdout, f"Missing exact prompt: {prompt1!r}"
        assert prompt2 in first.stdout, f"Missing exact prompt: {prompt2!r}"
        assert read_generated_lines() == ['#!/bin/bash', cmd2], "The builder did not honor n/y or overwrite correctly"
        assert os.stat(SH_SCRIPT_PATH).st_mode & stat.S_IXUSR, "The builder must make start_tunnels.sh executable"

        # Reverse the answers to prove each parsed entry is controlled independently.
        with open(SH_SCRIPT_PATH, 'w') as f:
            f.write("ANOTHER STALE FILE\n")
        os.chmod(SH_SCRIPT_PATH, 0o600)
        second = run_builder("y\nn\n")
        assert second.returncode == 0, f"builder failed: {second.stderr}"
        assert prompt1 in second.stdout and prompt2 in second.stdout, "Missing dynamically derived prompts"
        assert read_generated_lines() == ['#!/bin/bash', cmd1], "The builder did not honor y/n or overwrite correctly"
        assert os.stat(SH_SCRIPT_PATH).st_mode & stat.S_IXUSR, "The builder must set executable permission using its run"
    finally:
        with open(FSTAB_PATH, 'wb') as f:
            f.write(original_fstab)
        os.chmod(FSTAB_PATH, original_mode)

    # Preserve the original fixed interaction and leave its result for the next test.
    process = run_builder("y\ny\n")
    assert process.returncode == 0, f"builder failed on requested configuration: {process.stderr}"
    assert "Enable tunnel to 10.1.1.50:80 on local port 8080?" in process.stdout, "Missing or incorrect prompt for port 8080"
    assert "Enable tunnel to 192.168.100.10:5432 on local port 5432?" in process.stdout, "Missing or incorrect prompt for port 5432"
    assert "Enable tunnel to 10.1.1.50:80 on local port 8080? (y/n): " in process.stdout
    assert "Enable tunnel to 192.168.100.10:5432 on local port 5432? (y/n): " in process.stdout


def test_generated_bash_script():
    """Verify start_tunnels.sh is generated correctly and is executable."""
    assert os.path.isfile(SH_SCRIPT_PATH), f"{SH_SCRIPT_PATH} was not generated"

    st = os.stat(SH_SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SH_SCRIPT_PATH} is not executable"

    with open(SH_SCRIPT_PATH, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"{SH_SCRIPT_PATH} is empty"
    assert lines[0] == "#!/bin/bash", f"{SH_SCRIPT_PATH} does not start with #!/bin/bash"

    content = "\n".join(lines)
    assert "ssh -L 8080:10.1.1.50:80 -N -T jump_web" in content or "ssh -L 8080:10.1.1.50:80 -N -T jump_web" in " ".join(lines), "Missing or incorrect ssh command for jump_web"
    assert "ssh -L 5432:192.168.100.10:5432 -N -f jump_db" in content or "ssh -L 5432:192.168.100.10:5432 -N -f jump_db" in " ".join(lines), "Missing or incorrect ssh command for jump_db"

    assert lines == [
        '#!/bin/bash',
        'ssh -L 8080:10.1.1.50:80 -N -T jump_web',
        'ssh -L 5432:192.168.100.10:5432 -N -f jump_db',
    ], "Generated script must contain exactly the requested commands"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
