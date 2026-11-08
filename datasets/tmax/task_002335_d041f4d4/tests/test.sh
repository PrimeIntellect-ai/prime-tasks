#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import string
import subprocess
import tempfile


def copy_executable_with_libs(source, destination, root):
    source = shutil.which(source) if not os.path.isabs(source) else source
    assert source and os.path.isfile(source), f"Required trusted tool {source!r} is unavailable"

    target = os.path.join(root, destination.lstrip('/'))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copy2(source, target)

    ldd = subprocess.run(["ldd", source], capture_output=True, text=True, check=False)
    for library in set(re.findall(r"(/[^^\s()]+)", ldd.stdout)):
        if os.path.isfile(library):
            library_target = os.path.join(root, library.lstrip('/'))
            os.makedirs(os.path.dirname(library_target), exist_ok=True)
            shutil.copy2(library, library_target)


def expected_for(token):
    return b"VALID-" + token[::-1].encode("ascii").hex().upper().encode("ascii") + b"-ACK\n"


def test_auth_backend_fuzz_equivalence():
    oracle_path = "/app/auth_backend"
    agent_script = "/home/user/auth_backend.sh"

    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} is missing."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    with open(agent_script, "rb") as handle:
        script_data = handle.read()
    assert b"\x00" not in script_data, "Agent submission must be a text Bash script."
    first_line = script_data.splitlines()[0] if script_data.splitlines() else b""
    assert re.match(br"^#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env[ -S]+bash)(?:\s|$)", first_line), (
        "Agent submission must have a Bash shebang."
    )

    # Execute only the submitted script and trusted text-processing tools in a
    # clean chroot. The original binary and all other agent-created files are
    # deliberately unavailable to the submission during verification.
    with tempfile.TemporaryDirectory(prefix="auth-sandbox-") as root:
        tools = [
            "bash", "env", "awk", "sed", "grep", "tr", "rev", "xxd",
            "cut", "fold", "od", "cat", "tac", "wc", "paste", "head",
            "tail", "sort", "uniq", "expr", "printf", "basename", "dirname"
        ]
        for tool in tools:
            source = shutil.which(tool)
            if source:
                copy_executable_with_libs(source, f"/usr/bin/{tool}", root)
                copy_executable_with_libs(source, f"/bin/{tool}", root)

        os.makedirs(os.path.join(root, "tmp"), mode=0o1777, exist_ok=True)
        os.makedirs(os.path.join(root, "dev"), exist_ok=True)
        open(os.path.join(root, "dev", "null"), "wb").close()

        sandbox_script = os.path.join(root, "auth_backend.sh")
        with open(sandbox_script, "wb") as handle:
            handle.write(script_data)
        os.chmod(sandbox_script, 0o755)

        rng = secrets.SystemRandom()
        chars = string.ascii_letters + string.digits
        tokens = [
            ''.join(rng.choice(chars) for _ in range(rng.randint(8, 16)))
            for _ in range(200)
        ]

        for token in tokens:
            expected_output = expected_for(token)

            # Preserve the original oracle equivalence assertion while also
            # deriving the expected answer independently.
            oracle_res = subprocess.run([oracle_path, token], capture_output=True, text=False)
            assert oracle_res.returncode == 0, f"Oracle failed on input '{token}'"
            assert oracle_res.stdout == expected_output, f"Oracle disagreed with derived output for '{token}'"

            agent_res = subprocess.run(
                ["chroot", root, "/auth_backend.sh", token],
                capture_output=True,
                text=False,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
            )
            assert agent_res.returncode == 0, (
                f"Agent script failed on input '{token}' with status {agent_res.returncode}.\n"
                f"stderr: {agent_res.stderr!r}"
            )
            actual_output = agent_res.stdout
            assert expected_output == actual_output, (
                f"Mismatch on input '{token}'.\n"
                f"Expected (hex): {expected_output.hex()}\n"
                f"Actual (hex): {actual_output.hex()}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
