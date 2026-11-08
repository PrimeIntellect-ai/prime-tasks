#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fnmatch
import os
import random
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile


def uncommented(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def parse_nginx(text):
    tokens = re.findall(r'[{};]|[^\s{};]+', uncommented(text))

    def parse_items(pos=0, nested=False):
        items = []
        while pos < len(tokens):
            if tokens[pos] == '}':
                assert nested, "Unexpected closing brace in Nginx configuration"
                return items, pos + 1
            words = []
            while pos < len(tokens) and tokens[pos] not in (';', '{', '}'):
                words.append(tokens[pos])
                pos += 1
            assert words, "Malformed Nginx configuration"
            assert pos < len(tokens), "Unterminated Nginx directive"
            if tokens[pos] == ';':
                items.append((words[0], words[1:], None))
                pos += 1
            elif tokens[pos] == '{':
                children, pos = parse_items(pos + 1, True)
                items.append((words[0], words[1:], children))
            else:
                raise AssertionError("Malformed Nginx configuration")
        assert not nested, "Unclosed block in Nginx configuration"
        return items, pos

    return parse_items()[0]


def test_nginx_config_updated():
    nginx_conf = "/home/user/edge_proxy/nginx.conf"
    assert os.path.isfile(nginx_conf), f"Nginx config missing at {nginx_conf}"
    with open(nginx_conf, 'r') as f:
        content = f.read()

    # Preserve the original assertion and additionally require an active directive.
    assert "unix:/home/user/run/app.sock" in content, "Nginx config does not point to the correct socket path 'unix:/home/user/run/app.sock'."

    tree = parse_nginx(content)
    http_blocks = [x for x in tree if x[0] == 'http' and x[2] is not None]
    assert http_blocks, "Nginx configuration has no active http block"
    backends = []
    for _, _, http_children in http_blocks:
        backends.extend(x for x in http_children
                        if x[0] == 'upstream' and x[1] == ['backend'] and x[2] is not None)
    assert backends, "Nginx configuration has no active upstream backend block"
    servers = [args for _, _, children in backends
               for name, args, sub in children
               if name == 'server' and sub is None]
    assert ['unix:/home/user/run/app.sock'] in servers, "The backend upstream lacks the required active server directive"
    assert all('unix:/tmp/backend.sock' not in args for args in servers), "The old backend socket is still actively configured"


def parse_logrotate(content):
    active = uncommented(content)
    blocks = []
    spans = []
    for match in re.finditer(r'([^{}]+)\{([^{}]*)\}', active, flags=re.S):
        header = match.group(1).strip()
        body = match.group(2)
        assert header, "Logrotate block has no log paths"
        paths = shlex.split(header)
        directives = [line.split() for line in body.splitlines() if line.strip()]
        blocks.append((paths, directives))
        spans.append(match.span())

    outside_parts = []
    end = 0
    for start, stop in spans:
        outside_parts.append(active[end:start])
        end = stop
    outside_parts.append(active[end:])
    outside = "\n".join(outside_parts)
    global_directives = [line.split() for line in outside.splitlines() if line.strip()]
    return global_directives, blocks


def directives_valid(directives):
    names = [parts[0] for parts in directives if parts]
    rotations = [parts[1:] for parts in directives if parts and parts[0] == 'rotate']
    return ('daily' in names and 'compress' in names and 'nocompress' not in names
            and 'missingok' in names and rotations == [['7']])


def test_logrotate_config():
    logrotate_conf = "/home/user/logrotate.conf"
    assert os.path.isfile(logrotate_conf), f"Logrotate config missing at {logrotate_conf}"
    with open(logrotate_conf, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    assert "daily" in content, "Logrotate config missing 'daily' directive"
    assert "rotate 7" in content, "Logrotate config missing 'rotate 7' directive"
    assert "compress" in content, "Logrotate config missing 'compress' directive"
    assert "missingok" in content, "Logrotate config missing 'missingok' directive"
    has_wildcard = "/home/user/edge_proxy/logs/*.log" in content
    has_both = "/home/user/edge_proxy/logs/access.log" in content and "/home/user/edge_proxy/logs/error.log" in content
    assert has_wildcard or has_both, "Logrotate config does not apply to the correct log files (/home/user/edge_proxy/logs/access.log and error.log, or *.log)"

    global_directives, blocks = parse_logrotate(content)
    targets = ["/home/user/edge_proxy/logs/access.log", "/home/user/edge_proxy/logs/error.log"]
    for target in targets:
        matching = [(paths, body) for paths, body in blocks
                    if any(fnmatch.fnmatchcase(target, pattern) for pattern in paths)]
        assert matching, f"No active logrotate block applies to {target}"
        assert any(directives_valid(global_directives + body) for _, body in matching), \
            f"The active logrotate settings for {target} do not specify daily, rotate 7, compress, and missingok"

    proc = subprocess.run(['logrotate', '--debug', logrotate_conf], capture_output=True, text=True)
    assert proc.returncode == 0, f"logrotate rejects the configuration:\n{proc.stdout}\n{proc.stderr}"


def test_crontab_updated():
    try:
        output = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        output = ""

    # Preserve the original assertion, then exclude comments and duplicate runs.
    assert re.search(r'\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/monitor\.sh', output), "Crontab does not contain the correct entry for monitor.sh running every 5 minutes"
    active = [line.strip() for line in output.splitlines()
              if line.strip() and not line.lstrip().startswith('#')]
    monitor_entries = []
    for line in active:
        match = re.match(r'^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$', line)
        if match and re.search(r'(^|\s)/home/user/monitor\.sh(?:\s|$)', match.group(6)):
            monitor_entries.append(match.groups())
    assert len(monitor_entries) == 1, "monitor.sh must have exactly one active crontab entry"
    assert monitor_entries[0][:5] == ('*/5', '*', '*', '*', '*'), "monitor.sh is not scheduled exactly every five minutes"


def expected_payload(t, h, p, l):
    checksum = (t + h + p + l) & 0xff
    return bytes([0xaa, 0xbb, checksum, 1 if t > 30 else 0,
                  t & 0xff, (t >> 8) & 0xff,
                  h & 0xff, (h >> 8) & 0xff,
                  p & 0xff, (p >> 8) & 0xff,
                  l & 0xff, (l >> 8) & 0xff,
                  0, 0, 0xcc, 0xdd])


def make_chroot(executable):
    root = tempfile.mkdtemp(prefix='encoder-root-')
    destination = os.path.join(root, 'encoder')
    shutil.copy2(executable, destination)
    os.chmod(destination, 0o755)

    ldd = subprocess.run(['ldd', executable], capture_output=True, text=True)
    if ldd.returncode == 0:
        libraries = set(re.findall(r'(?<!\S)(/[^\s()]+)', ldd.stdout))
        for library in libraries:
            if not os.path.isfile(library):
                continue
            target = os.path.join(root, library.lstrip('/'))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.realpath(library), target)
    return root


def run_isolated(root, input_data):
    def enter_chroot():
        os.chroot(root)
        os.chdir('/')
    return subprocess.run(['/encoder'], input=input_data, capture_output=True,
                          timeout=3, preexec_fn=enter_chroot)


def assert_cases(root, cases, label):
    for t, h, p, l in cases:
        input_data = f"{t} {h} {p} {l}\n".encode()
        proc = run_isolated(root, input_data)
        assert proc.returncode == 0, f"{label} failed on input {t} {h} {p} {l}"
        assert proc.stdout == expected_payload(t, h, p, l), \
            f"{label} output mismatch on input {t} {h} {p} {l}: {proc.stdout.hex()}"


def test_fuzz_equivalence_encoder():
    oracle_path = "/app/legacy_encoder"
    agent_path = "/home/user/encoder"
    source_path = "/home/user/encoder.cpp"

    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary is not executable at {agent_path}"
    assert os.path.isfile(source_path), f"C++ source missing at {source_path}"
    with open(agent_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Agent executable must be a native ELF binary"
    assert not os.path.samefile(agent_path, oracle_path), "Agent executable must not be the legacy binary"
    with open(agent_path, 'rb') as a, open(oracle_path, 'rb') as o:
        assert a.read() != o.read(), "Agent executable is byte-identical to the legacy binary"

    # Preserve the original deterministic oracle comparison.
    random.seed(42)
    for _ in range(1000):
        t = random.randint(0, 10000)
        h = random.randint(0, 10000)
        p = random.randint(0, 10000)
        l = random.randint(0, 10000)
        input_data = f"{t} {h} {p} {l}\n".encode('utf-8')
        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, capture_output=True)
        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Output mismatch on input '{input_data.decode().strip()}'.\n"
            f"Oracle stdout: {oracle_proc.stdout.hex()}\n"
            f"Agent stdout:  {agent_proc.stdout.hex()}"
        )

    source_binary = tempfile.mktemp(prefix='encoder-source-')
    compile_proc = subprocess.run(
        ['g++', '-std=c++17', '-O2', '-static', source_path, '-o', source_binary],
        capture_output=True, text=True)
    assert compile_proc.returncode == 0, f"encoder.cpp does not compile as native C++:\n{compile_proc.stderr}"

    agent_root = make_chroot(agent_path)
    source_root = make_chroot(source_binary)
    try:
        cases = [(0, 0, 0, 0), (30, 10000, 1, 9999), (31, 0, 10000, 255),
                 (10000, 10000, 10000, 10000), (255, 256, 257, 258)]
        rng = secrets.SystemRandom()
        cases.extend(tuple(rng.randint(0, 10000) for _ in range(4)) for _ in range(128))
        # Chroot isolation ensures neither artifact can delegate to the legacy encoder
        # or to a copied external executable.
        assert_cases(agent_root, cases, "Submitted encoder")
        assert_cases(source_root, cases, "Program compiled from encoder.cpp")
    finally:
        shutil.rmtree(agent_root, ignore_errors=True)
        shutil.rmtree(source_root, ignore_errors=True)
        if os.path.exists(source_binary):
            os.unlink(source_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
