#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import tarfile
import pytest


def test_fuzz_equivalence():
    """Test that new_router matches legacy_router on 10000 random inputs."""
    legacy_router = "/app/legacy_router"
    new_router_src = "/home/user/new_router.c"
    new_router = "/home/user/new_router"

    assert os.path.exists(legacy_router), f"Oracle missing at {legacy_router}"
    assert os.path.exists(new_router_src), f"Agent source missing at {new_router_src}"

    # Compile the agent's code if the binary doesn't exist or just to be sure
    compile_proc = subprocess.run(["gcc", new_router_src, "-o", new_router], capture_output=True)
    assert compile_proc.returncode == 0, f"Failed to compile {new_router_src}:\n{compile_proc.stderr.decode()}"

    assert os.path.exists(new_router), f"Agent binary missing at {new_router}"

    random.seed(42)
    charset = string.ascii_letters + string.digits

    for _ in range(10000):
        length = random.randint(1, 64)
        fuzz_input = ''.join(random.choice(charset) for _ in range(length))

        oracle_proc = subprocess.run([legacy_router, fuzz_input], capture_output=True, text=True)
        agent_proc = subprocess.run([new_router, fuzz_input], capture_output=True, text=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on input: {fuzz_input}"
        assert agent_proc.returncode == 0, f"Agent failed on input: {fuzz_input}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, f"Mismatch on input '{fuzz_input}': Expected '{oracle_out}', got '{agent_out}'"


def test_bashrc_env_var():
    """Verify ROUTER_MODE=migration is in .bashrc and exported by an interactive shell."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"Missing {bashrc_path}"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert "ROUTER_MODE=migration" in content, "ROUTER_MODE=migration not found in .bashrc"

    env = os.environ.copy()
    env.pop("ROUTER_MODE", None)
    proc = subprocess.run(
        ["bash", "--noprofile", "--rcfile", bashrc_path, "-ic", "/usr/bin/env"],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )
    assert proc.returncode == 0, f"Could not load {bashrc_path}:\n{proc.stderr}"
    assert "ROUTER_MODE=migration" in proc.stdout.splitlines(), \
        "ROUTER_MODE is not exported as migration by the user's shell profile"


def _parse_nginx(content):
    # Remove comments, tokenize directives/braces, and build a small syntax tree.
    content = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{};]|[^\s{};]+', content)
    pos = 0

    def parse_scope(needs_close=False):
        nonlocal pos
        nodes = []
        while pos < len(tokens):
            if tokens[pos] == "}":
                assert needs_close, "Unexpected closing brace in proxy.conf"
                pos += 1
                return nodes
            header = []
            while pos < len(tokens) and tokens[pos] not in ("{", "}", ";"):
                header.append(tokens[pos].strip('"\''))
                pos += 1
            assert header, "Malformed directive in proxy.conf"
            assert pos < len(tokens), "Unterminated directive in proxy.conf"
            if tokens[pos] == ";":
                pos += 1
                nodes.append((header, None))
            elif tokens[pos] == "{":
                pos += 1
                nodes.append((header, parse_scope(True)))
            else:
                raise AssertionError("Malformed block in proxy.conf")
        assert not needs_close, "Unclosed block in proxy.conf"
        return nodes

    tree = parse_scope()
    assert pos == len(tokens), "Could not parse all of proxy.conf"
    return tree


def _walk(nodes):
    for node in nodes:
        yield node
        if node[1] is not None:
            yield from _walk(node[1])


def test_proxy_conf():
    """Verify proxy.conf defines a real listener and proxies to all four backends."""
    conf_path = "/home/user/proxy.conf"
    assert os.path.exists(conf_path), f"Missing {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()

    assert "listen 9000" in content or "listen  9000" in content, "listen 9000 directive missing in proxy.conf"
    for port in [8080, 8081, 8082, 8083]:
        assert str(port) in content, f"Port {port} missing in proxy.conf"

    tree = _parse_nginx(content)
    all_nodes = list(_walk(tree))
    upstreams = {}
    for header, children in all_nodes:
        if children is not None and len(header) >= 2 and header[0] == "upstream":
            ports = []
            for directive, nested in children:
                if nested is None and len(directive) >= 2 and directive[0] == "server":
                    match = re.search(r":(\d+)$", directive[1])
                    if match:
                        ports.append(int(match.group(1)))
            upstreams[header[1]] = ports

    valid_upstreams = {
        name for name, ports in upstreams.items()
        if sorted(ports) == [8080, 8081, 8082, 8083]
    }
    assert valid_upstreams, \
        "proxy.conf must define an upstream with exactly the four backend ports 8080-8083"

    functional_server = False
    for header, children in all_nodes:
        if children is None or header != ["server"]:
            continue
        listens_9000 = any(
            nested is None and directive and directive[0] == "listen" and
            any(re.search(r"(?:^|:)9000$", value) for value in directive[1:])
            for directive, nested in children
        )
        targets = set()
        for directive, nested in _walk(children):
            if nested is None and len(directive) >= 2 and directive[0] == "proxy_pass":
                match = re.match(r"https?://([^/:;]+)", directive[1])
                if match:
                    targets.add(match.group(1))
        if listens_9000 and targets.intersection(valid_upstreams):
            functional_server = True
            break

    assert functional_server, \
        "No server listening on port 9000 proxy_passes to the four-port upstream"


def test_expect_script():
    """Execute the Expect automation and verify it exports the mode and invokes gcc."""
    exp_path = "/home/user/verify_deployment.exp"
    assert os.path.exists(exp_path), f"Missing {exp_path}"
    assert os.path.isfile(exp_path), f"{exp_path} is not a regular file"

    with open(exp_path, "r", errors="replace") as f:
        content = f.read()
    active = "\n".join(
        line for line in content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    assert re.search(r"(?m)^\s*spawn\b[^\n]*(?:/bin/bash|\bbash\b)", active), \
        "Expect script must spawn /bin/bash in a pseudo-terminal"
    assert re.search(r"(?m)^\s*send\b[^\n]*export\s+ROUTER_MODE(?:=|\s+)migration", active), \
        "Expect script must export ROUTER_MODE=migration in the spawned shell"
    assert re.search(r"(?m)^\s*send\b[^\n]*gcc[^\n]*new_router\.c", active), \
        "Expect script must send a command that compiles new_router.c"
    assert re.search(r"(?m)^\s*expect\b", active), \
        "Expect script must wait for and verify interactive results"
    assert "$?" in active or "&&" in active, \
        "Expect script must condition its success on a zero compilation exit status"

    fakebin = "/tmp/expect-verifier-bin"
    log_path = "/tmp/expect-gcc.log"
    os.makedirs(fakebin, exist_ok=True)
    with open(os.path.join(fakebin, "gcc"), "w") as f:
        f.write("#!/bin/bash\nprintf '%s|%s\\n' \"$ROUTER_MODE\" \"$*\" >> /tmp/expect-gcc.log\nexec /usr/bin/gcc \"$@\"\n")
    os.chmod(os.path.join(fakebin, "gcc"), 0o755)
    if os.path.exists(log_path):
        os.unlink(log_path)

    env = os.environ.copy()
    env.pop("ROUTER_MODE", None)
    env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
    proc = subprocess.run(
        ["expect", "-f", exp_path],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert proc.returncode == 0, \
        f"Expect deployment check failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.exists(log_path), "Expect script did not actually invoke gcc"
    with open(log_path, "r") as f:
        invocations = f.read().splitlines()
    assert any(line.startswith("migration|") and "new_router.c" in line for line in invocations), \
        "gcc was not invoked on new_router.c with ROUTER_MODE=migration exported"


def test_backup_script():
    """Verify backup_strategy.sh works and creates the correct tarball."""
    script_path = "/home/user/backup_strategy.sh"
    tar_path = "/home/user/backups/deploy_backup.tar.gz"

    assert os.path.exists(script_path), f"Missing {script_path}"

    # Run the backup script
    proc = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert proc.returncode == 0, f"Backup script failed:\n{proc.stderr}"

    assert os.path.exists(tar_path), f"Backup tarball not created at {tar_path}"

    # Check tarball contents
    with tarfile.open(tar_path, "r:gz") as tar:
        names = [os.path.basename(m.name) for m in tar.getmembers()]
        assert "proxy.conf" in names, "proxy.conf missing from backup tarball"
        assert "new_router.c" in names, "new_router.c missing from backup tarball"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
