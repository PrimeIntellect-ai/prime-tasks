#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess


def clear_spool():
    spool = "/home/user/mail_spool"
    os.makedirs(spool, exist_ok=True)
    for name in os.listdir(spool):
        path = os.path.join(spool, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def write_kib(path, kib):
    block = secrets.token_bytes(1024)
    with open(path, "wb") as f:
        for _ in range(kib):
            f.write(block)


def run_monitor(expected_line):
    migration_log = "/home/user/migration.log"
    sentinel = "preexisting-log-entry"
    with open(migration_log, "w") as f:
        f.write(sentinel + "\n")
    subprocess.run(["/home/user/storage_monitor.sh"], check=True, timeout=15)
    with open(migration_log, "r") as f:
        lines = f.read().splitlines()
    assert lines == [sentinel, expected_line], (
        "Monitor must append exactly one required status line; got: " + repr(lines)
    )


def parse_haproxy_sections(path):
    section_kinds = {"global", "defaults", "frontend", "backend", "listen"}
    sections = []
    current = None
    with open(path, "r") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            tokens = line.split()
            if tokens[0].lower() in section_kinds:
                current = {
                    "kind": tokens[0].lower(),
                    "name": tokens[1] if len(tokens) > 1 else None,
                    "directives": [],
                }
                sections.append(current)
            elif current is not None:
                current["directives"].append(tokens)
    return sections


def test_setup_script_exists_executable_generates_and_is_idempotent():
    path = "/home/user/setup_migration.sh"
    assert os.path.isfile(path), f"Setup script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Setup script {path} is not executable."

    for generated in ("/home/user/haproxy.cfg", "/home/user/storage_monitor.sh"):
        if os.path.lexists(generated):
            if os.path.isdir(generated) and not os.path.islink(generated):
                shutil.rmtree(generated)
            else:
                os.unlink(generated)

    subprocess.run([path], check=True, timeout=20)
    assert os.path.isfile("/home/user/haproxy.cfg"), "Setup did not generate haproxy.cfg"
    assert os.path.isfile("/home/user/storage_monitor.sh"), "Setup did not generate storage_monitor.sh"

    first = {}
    for generated in ("/home/user/haproxy.cfg", "/home/user/storage_monitor.sh"):
        with open(generated, "rb") as f:
            first[generated] = (f.read(), stat.S_IMODE(os.stat(generated).st_mode))

    subprocess.run([path], check=True, timeout=20)
    for generated in first:
        with open(generated, "rb") as f:
            second = (f.read(), stat.S_IMODE(os.stat(generated).st_mode))
        assert second == first[generated], f"Repeated setup changed generated artifact {generated}"


def test_haproxy_cfg_contents():
    path = "/home/user/haproxy.cfg"
    assert os.path.isfile(path), f"HAProxy config {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "timeout connect 5000ms" in content, "Missing 'timeout connect 5000ms' in haproxy.cfg"
    assert "timeout client 10000ms" in content, "Missing 'timeout client 10000ms' in haproxy.cfg"
    assert "timeout server 10000ms" in content, "Missing 'timeout server 10000ms' in haproxy.cfg"
    assert "frontend email_front" in content, "Missing 'frontend email_front' in haproxy.cfg"
    assert "bind 127.0.0.1:8080" in content, "Missing 'bind 127.0.0.1:8080' in haproxy.cfg"
    assert "backend email_back" in content, "Missing 'backend email_back' in haproxy.cfg"
    assert "127.0.0.1:8081" in content, "Missing node1 at '127.0.0.1:8081' in haproxy.cfg"
    assert "127.0.0.1:8082" in content, "Missing node2 at '127.0.0.1:8082' in haproxy.cfg"
    assert "roundrobin" in content, "Missing 'roundrobin' load balancing in haproxy.cfg"

    validation = subprocess.run(
        ["haproxy", "-c", "-f", path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert validation.returncode == 0, "Invalid HAProxy configuration:\n" + validation.stdout

    sections = parse_haproxy_sections(path)
    defaults = [s for s in sections if s["kind"] == "defaults"]
    assert defaults, "No active defaults section found"
    required_timeouts = {
        ("timeout", "connect", "5000ms"),
        ("timeout", "client", "10000ms"),
        ("timeout", "server", "10000ms"),
    }
    assert any(required_timeouts.issubset({tuple(d[:3]) for d in s["directives"] if len(d) >= 3}) for s in defaults), (
        "Required timeout directives must be active in one defaults section"
    )

    frontends = [s for s in sections if s["kind"] == "frontend" and s["name"] == "email_front"]
    assert frontends, "No active frontend named email_front found"
    assert any(any(d[:2] == ["bind", "127.0.0.1:8080"] for d in s["directives"]) for s in frontends), (
        "email_front must actively bind 127.0.0.1:8080"
    )
    assert any(any(d[:2] == ["default_backend", "email_back"] for d in s["directives"]) for s in frontends), (
        "email_front must route to email_back"
    )

    backends = [s for s in sections if s["kind"] == "backend" and s["name"] == "email_back"]
    assert backends, "No active backend named email_back found"
    assert any(any(d[:2] == ["balance", "roundrobin"] for d in s["directives"]) for s in backends), (
        "email_back must actively use roundrobin"
    )
    assert any(any(d[:3] == ["server", "node1", "127.0.0.1:8081"] for d in s["directives"]) for s in backends), (
        "email_back must define node1 at 127.0.0.1:8081"
    )
    assert any(any(d[:3] == ["server", "node2", "127.0.0.1:8082"] for d in s["directives"]) for s in backends), (
        "email_back must define node2 at 127.0.0.1:8082"
    )


def test_storage_monitor_script_exists_and_executable():
    path = "/home/user/storage_monitor.sh"
    assert os.path.isfile(path), f"Monitor script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Monitor script {path} is not executable."


def test_storage_monitor_under_limits():
    monitor_script = "/home/user/storage_monitor.sh"
    mail_spool = "/home/user/mail_spool"
    migration_log = "/home/user/migration.log"
    open(migration_log, "w").close()
    clear_spool()
    small_file = os.path.join(mail_spool, "small.txt")
    with open(small_file, "wb") as f:
        f.write(b"0" * 500 * 1024)
    subprocess.run([monitor_script], check=True)
    with open(migration_log, "r") as f:
        log_content = f.read()
    assert "[OK] Storage within limits." in log_content, "Expected '[OK] Storage within limits.' in migration.log"
    assert os.path.isfile(small_file), "small.txt should not have been deleted."


def test_storage_monitor_exceeding_limits():
    monitor_script = "/home/user/storage_monitor.sh"
    mail_spool = "/home/user/mail_spool"
    migration_log = "/home/user/migration.log"
    open(migration_log, "w").close()
    clear_spool()
    large_file = os.path.join(mail_spool, "large.txt")
    with open(large_file, "wb") as f:
        f.write(b"0" * 2000 * 1024)
    subprocess.run([monitor_script], check=True)
    with open(migration_log, "r") as f:
        log_content = f.read()
    assert "[WARN] Storage quota exceeded. Clearing spool." in log_content, "Expected '[WARN] Storage quota exceeded. Clearing spool.' in migration.log"
    files = os.listdir(mail_spool)
    assert len(files) == 0, f"mail_spool should be empty, but found: {files}"


def test_storage_monitor_randomized_inputs():
    spool = "/home/user/mail_spool"
    rng = secrets.SystemRandom()

    for _ in range(3):
        clear_spool()
        total = rng.randint(180, 850)
        first = rng.randint(1, total - 1)
        names = [secrets.token_hex(9), "." + secrets.token_hex(9)]
        paths = [os.path.join(spool, names[0]), os.path.join(spool, names[1])]
        write_kib(paths[0], first)
        write_kib(paths[1], total - first)
        run_monitor("[OK] Storage within limits.")
        assert all(os.path.isfile(p) for p in paths), "Under-limit files must remain intact"

    for _ in range(3):
        clear_spool()
        total = rng.randint(1250, 1900)
        first = rng.randint(100, total - 200)
        second = rng.randint(50, total - first - 1)
        sizes = [first, second, total - first - second]
        names = [secrets.token_hex(9), "." + secrets.token_hex(9), secrets.token_hex(9)]
        for name, size in zip(names, sizes):
            write_kib(os.path.join(spool, name), size)
        run_monitor("[WARN] Storage quota exceeded. Clearing spool.")
        assert os.listdir(spool) == [], "Every file, including hidden files, must be deleted over quota"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
