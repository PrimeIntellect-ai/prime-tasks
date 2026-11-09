#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import re
import string
import subprocess
import tempfile


def test_locale_installed():
    """Ensure the fr_FR.UTF-8 locale is installed and available."""
    result = subprocess.run(["locale", "-a"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run locale -a"
    locales = result.stdout.lower()
    assert "fr_fr.utf8" in locales or "fr_fr.utf-8" in locales, "Locale fr_FR.UTF-8 is not installed or generated."


def test_logrotate_config():
    """Check the logrotate configuration for daily rotation and 7 days retention."""
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"Logrotate config missing at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "daily" in content, "logrotate.conf is missing 'daily' directive."
    assert "rotate 7" in content, "logrotate.conf is missing 'rotate 7' directive."
    assert "/home/user/logs/" in content or "/home/user/logs/*" in content, "logrotate.conf does not target /home/user/logs/"

    # Ensure the required directives are active in the block targeting the logs,
    # rather than merely appearing in comments or an unrelated block.
    uncommented = re.sub(r"#.*", "", content)
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", uncommented, flags=re.S)
    matching = [(header, body) for header, body in blocks if "/home/user/logs/" in header]
    assert matching, "No logrotate rule targets files under /home/user/logs/"
    assert any(
        re.search(r"(?m)^\s*daily\s*$", body)
        and re.search(r"(?m)^\s*rotate\s+7\s*$", body)
        for _, body in matching
    ), "The /home/user/logs/ rule must rotate daily and retain 7 rotations."

    result = subprocess.run(["logrotate", "--debug", conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Invalid logrotate configuration:\n{result.stdout}\n{result.stderr}"


def test_parser_source_fixed():
    """Exercise the required vendored parser source directly."""
    parser_path = "/app/log-router-v1.2/src/parser.py"
    assert os.path.isfile(parser_path), f"Vendored parser missing at {parser_path}"

    spec = importlib.util.spec_from_file_location("vendored_log_router_parser", parser_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse_line", None)), "parser.py does not expose parse_line"

    rejection = "sshd[123]: Disconnecting: Too many authentication failures fr_FR.UTF-8"
    assert module.parse_line(rejection) == (
        f"ROUTING_DIRECTIVE: REJECT {rejection} OFFSET: +0100"
    )

    ordinary = "sshd[456]: accepted publickey for user fr_FR.UTF-8"
    assert module.parse_line(ordinary) == (
        f"ROUTING_DIRECTIVE: ACCEPT {ordinary} OFFSET: +0100"
    )


def test_wrapper_script_exists():
    """Ensure the wrapper script exists and is executable."""
    script_path = "/home/user/process_logs.sh"
    assert os.path.exists(script_path), f"Wrapper script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Wrapper script {script_path} is not executable"


def generate_log_lines(n):
    random.seed(42)
    lines = []
    for _ in range(n):
        length = random.randint(50, 500)
        base = "".join(random.choices(string.ascii_letters + string.digits + " :-", k=length))

        if random.random() < 0.4:
            base += " Disconnecting: Too many authentication failures "
        elif random.random() < 0.4:
            base += " Disconnecting: Too many failures "

        if random.random() < 0.5:
            base += " fr_FR.UTF-8 "
        else:
            base += " en_US.UTF-8 "

        lines.append(base)
    return lines


def test_fuzz_equivalence():
    """Fuzz both the protected oracle and the agent's wrapper script."""
    oracle_path = "/tests/log-router-oracle"
    agent_script = "/home/user/process_logs.sh"

    assert os.path.exists(oracle_path), f"Oracle program missing at {oracle_path}"

    lines = generate_log_lines(1000)
    chunk_size = 100
    chunks = [lines[i:i + chunk_size] for i in range(0, len(lines), chunk_size)]

    for i, chunk in enumerate(chunks):
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            tmp.write("\n".join(chunk) + "\n")
            tmp_path = tmp.name

        try:
            oracle_res = subprocess.run([oracle_path, tmp_path], capture_output=True, text=True)
            agent_res = subprocess.run([agent_script, tmp_path], capture_output=True, text=True)

            assert agent_res.returncode == oracle_res.returncode, (
                f"Return code mismatch on chunk {i}.\n"
                f"Oracle exited with {oracle_res.returncode}, Agent exited with {agent_res.returncode}.\n"
                f"Agent stderr: {agent_res.stderr}"
            )

            assert agent_res.stdout == oracle_res.stdout, (
                f"Output mismatch on chunk {i}.\n"
                f"--- Oracle Output ---\n{oracle_res.stdout}\n"
                f"--- Agent Output ---\n{agent_res.stdout}\n"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
