#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

DAEMON = "/home/user/lb_daemon"
SOURCE = "/home/user/lb_daemon.c"


def run_daemon(path, env):
    return subprocess.run([path], env=env, capture_output=True, text=True, timeout=10)


def assert_daemon_behavior(path):
    env = os.environ.copy()
    env.pop("UPSTREAM_CONF", None)
    process = run_daemon(path, env)
    assert process.returncode == 2, (
        f"Expected exit code 2 when UPSTREAM_CONF is missing, got {process.returncode}."
    )
    assert process.stderr.strip() != "", (
        "Expected an error message on stderr when UPSTREAM_CONF is missing."
    )

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as conf:
        conf.write("upstream1:127.0.0.1:9001\n")
        conf_path = conf.name

    try:
        env = os.environ.copy()
        env["UPSTREAM_CONF"] = conf_path
        env.pop("LB_PORT", None)
        process = run_daemon(path, env)
        assert process.returncode == 0, f"Expected exit code 0, got {process.returncode}."
        assert "8080" in process.stdout, (
            "Expected default port 8080 in output when LB_PORT is not set."
        )

        random_port = str(10000 + secrets.randbelow(40000))
        env["LB_PORT"] = random_port
        process = run_daemon(path, env)
        assert process.returncode == 0, f"Expected exit code 0, got {process.returncode}."
        assert random_port in process.stdout, (
            f"Expected dynamically selected LB_PORT {random_port} in output."
        )
    finally:
        os.unlink(conf_path)


def test_lb_daemon_compiled_and_executable():
    """Check that lb_daemon is a native executable, not an impersonating script."""
    assert os.path.isfile(DAEMON), f"Executable {DAEMON} is missing."
    st = os.stat(DAEMON)
    assert bool(st.st_mode & stat.S_IXUSR), f"{DAEMON} is not executable."
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{DAEMON} is not a compiled ELF executable."


def test_fixed_c_source_compiles_and_works():
    """Compile the submitted C source and exercise answers chosen by the verifier."""
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."
    with open(SOURCE, "rb") as f:
        assert b"\x00" not in f.read(), f"{SOURCE} does not appear to be C source text."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "lb_daemon_rebuilt")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The submitted lb_daemon.c does not compile with gcc:\n"
            + compile_result.stderr
        )
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        assert_daemon_behavior(rebuilt)


def test_lb_daemon_behavior_no_conf():
    """Check that lb_daemon exits with code 2 and prints to stderr if UPSTREAM_CONF is not set."""
    env = os.environ.copy()
    env.pop("UPSTREAM_CONF", None)
    process = run_daemon(DAEMON, env)
    assert process.returncode == 2, f"Expected exit code 2 when UPSTREAM_CONF is missing, got {process.returncode}."
    assert process.stderr.strip() != "", "Expected an error message on stderr when UPSTREAM_CONF is missing."


def test_lb_daemon_behavior_with_conf_and_port():
    """Check that lb_daemon reads LB_PORT and UPSTREAM_CONF correctly."""
    conf_path = "/home/user/upstream.conf"
    if not os.path.exists(conf_path):
        with open(conf_path, "w") as f:
            f.write("dummy")

    env = os.environ.copy()
    env["UPSTREAM_CONF"] = conf_path
    env.pop("LB_PORT", None)

    process = run_daemon(DAEMON, env)
    assert process.returncode == 0, f"Expected exit code 0, got {process.returncode}."
    assert "8080" in process.stdout, "Expected default port 8080 in output when LB_PORT is not set."

    env["LB_PORT"] = "9090"
    process = run_daemon(DAEMON, env)
    assert process.returncode == 0, f"Expected exit code 0, got {process.returncode}."
    assert "9090" in process.stdout, "Expected custom port 9090 in output when LB_PORT is set."

    random_port = str(10000 + secrets.randbelow(40000))
    env["LB_PORT"] = random_port
    process = run_daemon(DAEMON, env)
    assert process.returncode == 0, f"Expected exit code 0, got {process.returncode}."
    assert random_port in process.stdout, f"Expected custom port {random_port} in output."


def test_upstream_conf_content():
    """Check if /home/user/upstream.conf contains the correct upstream ports."""
    path = "/home/user/upstream.conf"
    assert os.path.isfile(path), f"{path} is missing. The expect script might not have run successfully."

    with open(path, "r") as f:
        content = f.read()

    assert "upstream1:127.0.0.1:9001" in content, "Port 9001 missing for upstream 1."
    assert "upstream2:127.0.0.1:9002" in content, "Port 9002 missing for upstream 2."
    assert "upstream3:127.0.0.1:9003" in content, "Port 9003 missing for upstream 3."


def test_auto_init_exp_exists_and_automates_prompts():
    """Run the expect artifact against the required interactive program interface."""
    expect_path = "/home/user/auto_init.exp"
    init_path = "/home/user/init_upstream.sh"
    conf_path = "/home/user/upstream.conf"
    assert os.path.isfile(expect_path), f"{expect_path} is missing."

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "init_upstream.sh.original")
        transcript = os.path.join(td, "answers")
        marker = os.path.join(td, "spawned")
        shutil.move(init_path, backup)
        try:
            instrumented = f'''#!/bin/bash
printf "Enter upstream port 1: "
IFS= read -r p1
printf "Enter upstream port 2: "
IFS= read -r p2
printf "Enter upstream port 3: "
IFS= read -r p3
printf '%s\\n%s\\n%s\\n' "$p1" "$p2" "$p3" > {transcript!r}
printf 'instrumented child ran\\n' > {marker!r}
printf 'upstream1:127.0.0.1:%s\\n' "$p1" > /home/user/upstream.conf
printf 'upstream2:127.0.0.1:%s\\n' "$p2" >> /home/user/upstream.conf
printf 'upstream3:127.0.0.1:%s\\n' "$p3" >> /home/user/upstream.conf
printf 'Configuration saved to /home/user/upstream.conf\\n'
'''
            with open(init_path, "w") as f:
                f.write(instrumented)
            os.chmod(init_path, 0o755)
            if os.path.exists(conf_path):
                os.unlink(conf_path)

            result = subprocess.run(
                ["expect", expect_path],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, (
                "auto_init.exp failed when run with expect:\n"
                + result.stdout + result.stderr
            )
            assert os.path.isfile(marker), (
                "auto_init.exp did not launch /home/user/init_upstream.sh."
            )
            assert os.path.isfile(transcript), "The interactive prompts were not answered."
            with open(transcript) as f:
                assert f.read().splitlines() == ["9001", "9002", "9003"], (
                    "auto_init.exp did not provide 9001, 9002, and 9003 to the three prompts."
                )
            assert os.path.isfile(conf_path), "Running auto_init.exp did not generate upstream.conf."
            with open(conf_path) as f:
                assert f.read().splitlines() == [
                    "upstream1:127.0.0.1:9001",
                    "upstream2:127.0.0.1:9002",
                    "upstream3:127.0.0.1:9003",
                ]
        finally:
            if os.path.exists(init_path):
                os.unlink(init_path)
            shutil.move(backup, init_path)


def test_bash_profile_exports():
    """Check both the requested text and the effective exported environment."""
    path = "/home/user/.bash_profile"
    assert os.path.isfile(path), f"{path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "LB_PORT=8080" in content, "LB_PORT=8080 not found in .bash_profile"
    assert "UPSTREAM_CONF=/home/user/upstream.conf" in content, "UPSTREAM_CONF=/home/user/upstream.conf not found in .bash_profile"

    command = r'''
unset LB_PORT UPSTREAM_CONF
source /home/user/.bash_profile
[[ "$LB_PORT" == "8080" ]]
[[ "$UPSTREAM_CONF" == "/home/user/upstream.conf" ]]
export -p | grep -q '^declare -x LB_PORT="8080"$'
export -p | grep -q '^declare -x UPSTREAM_CONF="/home/user/upstream.conf"$'
'''
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", command],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        ".bash_profile does not actually export the required values:\n"
        + result.stdout + result.stderr
    )


class MockHealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            if self.server.return_200:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"OK")
            else:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"ERROR")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def test_health_check_sh():
    """Test the health_check.sh script by mocking an HTTP server."""
    script_path = "/home/user/health_check.sh"
    log_path = "/home/user/health.log"

    assert os.path.isfile(script_path), f"{script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    if os.path.exists(log_path):
        os.remove(log_path)

    server = HTTPServer(('127.0.0.1', 8080), MockHealthHandler)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    try:
        server.return_200 = True
        subprocess.run([script_path], check=False, timeout=15)

        assert os.path.isfile(log_path), f"{log_path} was not created."
        with open(log_path, "r") as f:
            lines = f.readlines()
        assert len(lines) >= 1, "Log file is empty after successful request."
        assert lines[-1] == "UP\n", f"Expected 'UP\\n' in log, got {repr(lines[-1])}"

        server.return_200 = False
        subprocess.run([script_path], check=False, timeout=15)

        with open(log_path, "r") as f:
            lines = f.readlines()
        assert len(lines) >= 2, "Log file did not append after failed request."
        assert lines[-1] == "DOWN\n", f"Expected 'DOWN\\n' in log, got {repr(lines[-1])}"

    finally:
        server.shutdown()
        server.server_close()
        server_thread.join()

    subprocess.run([script_path], check=False, timeout=15)
    with open(log_path, "r") as f:
        lines = f.readlines()
    assert lines[-1] == "DOWN\n", f"Expected 'DOWN\\n' in log when server is unreachable, got {repr(lines[-1])}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
