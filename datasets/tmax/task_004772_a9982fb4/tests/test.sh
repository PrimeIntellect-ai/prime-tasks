#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import signal
import subprocess
import random
import tempfile
import time
import uuid


def run_program(path, data, timeout=3):
    return subprocess.run([path], input=data, capture_output=True, timeout=timeout)


def test_fuzz_equivalence_sec_logger():
    oracle_path = "/app/sec_logger"
    agent_path = "/home/user/sec_logger_clone"

    assert os.path.exists(agent_path), f"Agent binary {agent_path} does not exist."
    assert os.path.isfile(agent_path), f"{agent_path} is not a file."
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable."
    assert open(agent_path, "rb").read() != open(oracle_path, "rb").read(), \
        "The submitted binary must not be a byte-identical copy of /app/sec_logger."

    random.seed(42)
    cases = [b""]
    for i in range(100):
        length = random.randint(1, 4096)
        cases.append(bytes(random.getrandbits(8) for _ in range(length)))

    expected = []
    for i, input_data in enumerate(cases):
        oracle_proc = run_program(oracle_path, input_data, timeout=2)
        agent_proc = run_program(agent_path, input_data, timeout=2)

        assert oracle_proc.returncode == agent_proc.returncode, f"Return code mismatch on iteration {i}"
        assert oracle_proc.stdout == agent_proc.stdout, f"Output mismatch on iteration {i} for input length {len(input_data)}"
        expected.append((oracle_proc.returncode, oracle_proc.stdout))

    # The installed clone must work without invoking the original binary.
    hidden_oracle = os.path.join("/dev/shm", ".sec_logger_oracle_" + uuid.uuid4().hex)
    os.replace(oracle_path, hidden_oracle)
    try:
        for i in [0, 1, 17, 53, 100]:
            proc = run_program(agent_path, cases[i])
            assert (proc.returncode, proc.stdout) == expected[i], \
                f"Installed clone is not standalone on corpus case {i}."
    finally:
        os.replace(hidden_oracle, oracle_path)


def test_c_source_exists_compiles_and_is_standalone():
    source_path = "/home/user/sec_logger_clone.c"
    agent_path = "/home/user/sec_logger_clone"
    oracle_path = "/app/sec_logger"

    assert os.path.exists(source_path), f"C source {source_path} does not exist."
    assert os.path.isfile(source_path), f"{source_path} is not a file."
    assert not os.path.islink(source_path), f"{source_path} must be an actual source file, not a symlink."

    source = open(source_path, "r", encoding="utf-8", errors="strict").read()
    assert source.strip(), "The C source is empty."
    assert re.search(r"\bmain\s*\(", source), "The source does not define a C main function."
    assert "/app/sec_logger" not in source, "The source must implement the transformation rather than invoke the oracle."
    assert not re.search(r"\b(system|popen|execl|execle|execlp|execv|execve|execvp|execvpe)\s*\(", source), \
        "The C implementation must not delegate its work to another process."

    compiled = os.path.join(tempfile.mkdtemp(prefix="source-build-"), "sec_logger_clone")
    build = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", source_path, "-o", compiled],
        capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"The submitted C source does not compile cleanly:\n{build.stderr}"

    rng = random.Random(8675309)
    cases = [b"", bytes(range(256))]
    cases.extend(bytes(rng.getrandbits(8) for _ in range(rng.randint(1, 2048))) for _ in range(30))
    expected = []
    for data in cases:
        proc = run_program(oracle_path, data)
        expected.append((proc.returncode, proc.stdout))

    # Hide both pre-existing executables so the freshly built source must contain
    # the implementation itself.
    hidden_oracle = os.path.join("/dev/shm", ".oracle_" + uuid.uuid4().hex)
    hidden_agent = os.path.join("/dev/shm", ".agent_" + uuid.uuid4().hex)
    os.replace(oracle_path, hidden_oracle)
    os.replace(agent_path, hidden_agent)
    try:
        for i, data in enumerate(cases):
            proc = run_program(compiled, data)
            assert (proc.returncode, proc.stdout) == expected[i], \
                f"Binary freshly compiled from sec_logger_clone.c is incorrect on case {i}."
    finally:
        os.replace(hidden_agent, agent_path)
        os.replace(hidden_oracle, oracle_path)


def test_expect_script_and_auth():
    expect_script = "/home/user/init.exp"
    conf_file = "/home/user/logger.conf"
    init_script = "/app/init_env.sh"

    assert os.path.exists(expect_script), f"Expect script {expect_script} does not exist."
    assert os.path.exists(conf_file), f"Configuration file {conf_file} does not exist."

    with open(conf_file, "r") as f:
        content = f.read().strip()
    assert "AUTH_OK=1" in content, f"Configuration file {conf_file} does not contain expected AUTH_OK=1. Was the expect script run correctly?"

    # Remove the fabricable result and execute the submitted Expect artifact.
    os.unlink(conf_file)
    proc = subprocess.run(["expect", expect_script], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, f"init.exp failed when executed: {proc.stdout}\n{proc.stderr}"
    assert os.path.exists(conf_file), "Executing init.exp did not generate logger.conf."
    assert open(conf_file).read().strip() == "AUTH_OK=1", "init.exp did not authenticate with the required credentials."

    # Exercise the interaction against fresh prompts and independently record
    # what the Expect script supplies, rather than trusting logger.conf alone.
    capture = "/tmp/init_credentials_" + uuid.uuid4().hex
    backup = "/tmp/init_env_" + uuid.uuid4().hex
    os.replace(init_script, backup)
    try:
        challenge = f'''#!/bin/bash
read -p "Username: " user
read -p "PIN: " pin
printf '%s\\n%s\\n' "$user" "$pin" > {capture}
if [ "$user" = "sysadmin" ] && [ "$pin" = "8080" ]; then
  echo "AUTH_OK=1" > /home/user/logger.conf
else
  echo "AUTH_FAILED=1" > /home/user/logger.conf
fi
'''
        with open(init_script, "w") as f:
            f.write(challenge)
        os.chmod(init_script, 0o755)
        if os.path.exists(conf_file):
            os.unlink(conf_file)
        proc = subprocess.run(["expect", expect_script], capture_output=True, text=True, timeout=10)
        assert proc.returncode == 0, "init.exp failed while responding to the initialization prompts."
        assert os.path.exists(capture), "init.exp did not actually run and interact with /app/init_env.sh."
        assert open(capture).read().splitlines() == ["sysadmin", "8080"], \
            "init.exp did not provide username sysadmin and PIN 8080 to the prompts."
        assert open(conf_file).read().strip() == "AUTH_OK=1"
    finally:
        if os.path.exists(init_script):
            os.unlink(init_script)
        os.replace(backup, init_script)
        if os.path.exists(capture):
            os.unlink(capture)

    # Leave the real generated configuration as the final state.
    if os.path.exists(conf_file):
        os.unlink(conf_file)
    proc = subprocess.run(["expect", expect_script], capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0
    assert open(conf_file).read().strip() == "AUTH_OK=1"


def _stop_existing_agent_processes():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [x.decode(errors="ignore") for x in raw.split(b"\0") if x]
            if "/home/user/supervisor.sh" in args or "/home/user/sec_logger_clone" in args:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def _write_fifo(path, payload):
    code = "import sys; f=open(sys.argv[1],'wb', buffering=0); f.write(sys.stdin.buffer.read()); f.close()"
    return subprocess.run(["python3", "-c", code, path], input=payload, capture_output=True, timeout=4)


def _wait_for_log(path, expected, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = open(path, "rb").read()
            if data == expected:
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    actual = open(path, "rb").read() if os.path.exists(path) else b"<missing>"
    raise AssertionError(f"Supervisor log mismatch: expected {expected!r}, got {actual!r}")


def test_supervisor_and_fifo():
    supervisor_script = "/home/user/supervisor.sh"
    fifo_path = "/home/user/input.fifo"
    log_path = "/home/user/logs/output.log"

    assert os.path.exists(supervisor_script), f"Supervisor script {supervisor_script} does not exist."
    assert os.access(supervisor_script, os.X_OK), f"Supervisor script {supervisor_script} is not executable."
    assert os.path.exists(fifo_path), f"FIFO {fifo_path} does not exist."
    assert stat.S_ISFIFO(os.stat(fifo_path).st_mode), f"{fifo_path} is not a named pipe (FIFO)."

    _stop_existing_agent_processes()
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    open(log_path, "wb").close()

    first = b"first supervisor message\x00\xff\n"
    second = b"second message after child EOF\x80\n"
    expected_first = run_program("/app/sec_logger", first).stdout
    expected_second = run_program("/app/sec_logger", second).stdout

    supervisor = subprocess.Popen(
        [supervisor_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        assert _write_fifo(fifo_path, first).returncode == 0
        _wait_for_log(log_path, expected_first)

        # Closing the first writer gives the clone EOF, so processing this second
        # writer verifies that the supervisor restarted the terminated child.
        assert _write_fifo(fifo_path, second).returncode == 0
        _wait_for_log(log_path, expected_first + expected_second)
        assert supervisor.poll() is None, "The supervisor exited instead of continuously supervising the clone."
    finally:
        try:
            os.killpg(supervisor.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            supervisor.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(supervisor.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_logrotate_config():
    logrotate_conf = "/home/user/logrotate.conf"
    assert os.path.exists(logrotate_conf), f"logrotate configuration {logrotate_conf} does not exist."

    with open(logrotate_conf, "r") as f:
        content = f.read()

    assert "/home/user/logs/output.log" in content, "logrotate.conf does not target /home/user/logs/output.log"

    directives = ["daily", "rotate 7", "compress", "missingok", "size 10k"]
    for directive in directives:
        assert directive.replace(" ", "") in content.replace(" ", "").replace("\t", ""), f"logrotate.conf is missing or has incorrect directive related to: {directive}"

    # Ensure logrotate itself accepts the submitted configuration.
    state = "/tmp/logrotate-state-" + uuid.uuid4().hex
    parsed = subprocess.run(
        ["logrotate", "--debug", "--state", state, logrotate_conf],
        capture_output=True, text=True, timeout=10
    )
    assert parsed.returncode == 0, f"logrotate rejects logrotate.conf:\n{parsed.stdout}\n{parsed.stderr}"

    # Parse the actual target block, ignoring comments, and reject conflicting or
    # duplicate effective settings that a keyword grep would incorrectly accept.
    cleaned = re.sub(r"(?m)#.*$", "", content)
    match = re.search(r"(?:^|\n)\s*/home/user/logs/output\.log\s*\{(.*?)\}", cleaned, re.S)
    assert match, "No logrotate block specifically targets /home/user/logs/output.log."
    lines = [re.sub(r"\s+", " ", line.strip()).lower() for line in match.group(1).splitlines() if line.strip()]

    assert lines.count("daily") == 1, "The output.log block must specify daily exactly once."
    assert [x for x in lines if x.startswith("rotate ")] == ["rotate 7"], "The output.log block must retain exactly 7 rotations."
    assert lines.count("compress") == 1 and "nocompress" not in lines, "Compression must be enabled."
    assert lines.count("missingok") == 1 and "nomissingok" not in lines, "missingok must be enabled."
    assert [x for x in lines if x.startswith("size ")] == ["size 10k"], "The size threshold must be exactly 10k."
    assert not any(x in lines for x in ("hourly", "weekly", "monthly", "yearly")), \
        "A conflicting rotation interval is present in the output.log block."


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
