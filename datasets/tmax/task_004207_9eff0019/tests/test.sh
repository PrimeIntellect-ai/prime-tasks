#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import shutil
import string
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=15, **kwargs)


def extract_token():
    result = run(["tesseract", "/app/token_spec.png", "stdout"], text=True, errors="replace")
    assert result.returncode == 0, result.stderr
    match = re.search(r"TOKEN\s*:\s*([A-Z0-9]+)", result.stdout.upper())
    assert match, f"Could not extract token from token_spec.png: {result.stdout!r}"
    return match.group(1).encode("ascii")


def expected_output(value, token):
    return b"PROCESSED: " + value[::-1] + b" | AUTH: " + token + b"\n"


def check_processor(path, cases, token):
    assert os.path.isfile(path), f"Processor {path} is missing."
    assert os.access(path, os.X_OK), f"Processor {path} is not executable."

    no_arg = run([path])
    assert no_arg.returncode != 0, "Processor must reject calls without an argument."

    too_many = run([path, b"one", b"two"])
    assert too_many.returncode != 0, "Processor must reject calls with more than one argument."

    for value in cases:
        result = run([path, value])
        assert result.returncode == 0, (
            f"Processor exited with {result.returncode} for {value!r}; stderr={result.stderr!r}"
        )
        assert result.stdout == expected_output(value, token), (
            f"Output mismatch for {value!r}: got {result.stdout!r}, "
            f"expected {expected_output(value, token)!r}"
        )
        assert result.stderr == b"", f"Unexpected stderr for {value!r}: {result.stderr!r}"


def test_processor_fuzz_equivalence():
    source = "/home/user/src/processor.c"
    agent_prog = "/home/user/bin/processor"

    assert os.path.isfile(source), f"Required C source {source} is missing."
    assert os.path.isfile(agent_prog), f"Agent program {agent_prog} is missing."
    assert os.access(agent_prog, os.X_OK), f"Agent program {agent_prog} is not executable."

    token = extract_token()
    random.seed(42)
    chars = (string.ascii_letters + string.digits + string.punctuation + " ").encode("ascii")
    cases = [b"", b"hello", b"a b", b"!@#$%^&*()"]
    for _ in range(100):
        length = random.randint(1, 100)
        cases.append(bytes(random.choice(chars) for _ in range(length)))

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "processor")
        compiled = run(["gcc", "-std=c11", "-O2", source, "-o", rebuilt], text=True, errors="replace")
        assert compiled.returncode == 0, (
            f"The submitted processor.c does not compile.\nstdout: {compiled.stdout}\n"
            f"stderr: {compiled.stderr}"
        )
        check_processor(rebuilt, cases, token)

    check_processor(agent_prog, cases, token)


def nginx_tokens(content):
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    return re.findall(r'"(?:\\.|[^"\\])*"|[{};]|[^\s{};]+', uncommented)


def has_process_fastcgi(tokens):
    for opening in range(len(tokens)):
        if tokens[opening] != "{":
            continue
        start = opening - 1
        while start >= 0 and tokens[start] not in ("{", "}", ";"):
            start -= 1
        header = tokens[start + 1:opening]
        if not header or header[0] != "location" or "/process" not in header:
            continue

        depth = 1
        statement = []
        for token in tokens[opening + 1:]:
            if token == "{":
                depth += 1
                statement = []
            elif token == "}":
                depth -= 1
                statement = []
                if depth == 0:
                    break
            elif depth == 1 and token == ";":
                if statement == ["fastcgi_pass", "127.0.0.1:9000"]:
                    return True
                statement = []
            elif depth == 1:
                statement.append(token)
        
    return False


def test_nginx_config_fixed():
    conf_path = "/home/user/nginx/conf/nginx.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "fastcgi_pass 127.0.0.1:9000;" in content, "nginx.conf does not contain the fixed fastcgi_pass port 9000."
    assert "9099" not in content, "nginx.conf still contains the broken port 9099."

    syntax = run(["nginx", "-t", "-p", "/home/user/nginx/", "-c", "conf/nginx.conf"], text=True, errors="replace")
    assert syntax.returncode == 0, f"Invalid Nginx configuration:\n{syntax.stdout}\n{syntax.stderr}"
    assert has_process_fastcgi(nginx_tokens(content)), (
        "The valid /process location does not directly use fastcgi_pass 127.0.0.1:9000."
    )


def test_logrotate_config():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/home/user/nginx/logs/" in content and ".log" in content, "Logrotate config does not target the correct log files (e.g. /home/user/nginx/logs/*.log)."
    directives = ["daily", "rotate 7", "compress", "missingok"]
    for directive in directives:
        assert re.search(r"\b" + directive.replace(" ", r"\s+") + r"\b", content), f"Logrotate config does not specify '{directive}'."

    logs_dir = "/home/user/nginx/logs"
    os.makedirs(logs_dir, exist_ok=True)
    probe = os.path.join(logs_dir, "verifier_probe.log")
    with open(probe, "wb") as f:
        f.write(b"logrotate verification data\n")

    with tempfile.TemporaryDirectory() as tmp:
        debug_state = os.path.join(tmp, "debug.state")
        debug = run(["logrotate", "--debug", "-s", debug_state, conf_path], text=True, errors="replace")
        debug_text = debug.stdout + "\n" + debug.stderr
        assert debug.returncode == 0, f"Invalid logrotate configuration:\n{debug_text}"
        assert re.search(r"/home/user/nginx/logs/\*?\.log", debug_text), (
            "Parsed logrotate configuration does not target /home/user/nginx/logs/*.log."
        )
        assert re.search(r"(?:daily|after\s+1\s+days?)", debug_text, re.I), (
            "Parsed logrotate policy is not daily."
        )
        assert re.search(r"7\s+rotations", debug_text, re.I), (
            "Parsed logrotate policy does not retain 7 rotations."
        )

        rotate_state = os.path.join(tmp, "rotate.state")
        rotated = run(["logrotate", "-f", "-v", "-s", rotate_state, conf_path], text=True, errors="replace")
        assert rotated.returncode == 0, f"Log rotation failed:\n{rotated.stdout}\n{rotated.stderr}"
        compressed = glob.glob("/home/user/**/verifier_probe.log*.gz", recursive=True)
        assert compressed, "A forced rotation did not produce a compressed old verifier_probe.log."

        # With every current .log absent, missingok must keep logrotate successful.
        holding = os.path.join(tmp, "held_logs")
        os.mkdir(holding)
        held = []
        for path in glob.glob(os.path.join(logs_dir, "*.log")):
            destination = os.path.join(holding, os.path.basename(path))
            shutil.move(path, destination)
            held.append((destination, path))
        try:
            missing = run(["logrotate", "-f", "-s", os.path.join(tmp, "missing.state"), conf_path], text=True, errors="replace")
            assert missing.returncode == 0, (
                "Logrotate reports an error when matching log files are missing; missingok is not effective.\n"
                f"{missing.stdout}\n{missing.stderr}"
            )
        finally:
            for source, destination in held:
                shutil.move(source, destination)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
