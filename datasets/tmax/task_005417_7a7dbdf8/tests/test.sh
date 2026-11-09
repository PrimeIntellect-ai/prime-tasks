#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import subprocess
import tempfile

ORACLE = "/app/legacy_extractor"
AGENT = "/home/user/extractor"
N = 100


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_final_state():
    # Preserve the original artifact and executable checks.
    assert os.path.isfile(AGENT), f"Agent program {AGENT} does not exist or is not a file"
    assert os.access(AGENT, os.X_OK), f"Agent program {AGENT} is not executable"
    assert os.path.isfile(ORACLE), f"Oracle {ORACLE} does not exist"
    assert os.access(ORACLE, os.X_OK), f"Oracle {ORACLE} is not executable"

    oracle_digest = digest(ORACLE)
    assert digest(AGENT) != oracle_digest, "Submitted replacement is byte-identical to the legacy oracle"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        # Test inputs must remain readable after dropping privileges for the agent.
        os.chmod(tmpdir, 0o755)
        cases = []

        # Build the full corpus and obtain the oracle answers before removing it.
        for i in range(N):
            has_meta = random.random() < 0.8
            elf_path = os.path.join(tmpdir, f"test_{i}.elf")
            c_path = os.path.join(tmpdir, f"test_{i}.c")
            with open(c_path, "w") as f:
                f.write("int main() { return 0; }\n")

            subprocess.run(["gcc", c_path, "-o", elf_path], check=True, capture_output=True)

            if has_meta:
                length = random.randint(0, 1024)
                chars = []
                for _ in range(length):
                    c = random.choice([
                        random.randint(0x0020, 0x007E),
                        random.randint(0x00A0, 0x00FF),
                        random.randint(0x1F300, 0x1F64F),
                    ])
                    chars.append(chr(c))
                text = "".join(chars)
                utf16_bytes = text.encode("utf-16le")
                xored = bytes([b ^ 0x5A for b in utf16_bytes])

                meta_path = os.path.join(tmpdir, f"test_{i}.meta")
                with open(meta_path, "wb") as f:
                    f.write(xored)

                subprocess.run(
                    ["objcopy", "--add-section", f".pkg_meta={meta_path}", elf_path],
                    check=True,
                    capture_output=True,
                )

            oracle_res = subprocess.run([ORACLE, elf_path], capture_output=True)
            cases.append((i, has_meta, elf_path, oracle_res))

        # The replacement is exercised only after the legacy executable is gone.
        # Running it unprivileged also prevents it from recreating /app/legacy_extractor.
        os.unlink(ORACLE)
        assert not os.path.exists(ORACLE)

        for i, has_meta, elf_path, oracle_res in cases:
            agent_res = subprocess.run(
                [AGENT, elf_path],
                capture_output=True,
                preexec_fn=demote_to_user,
            )

            assert agent_res.returncode == oracle_res.returncode, (
                f"Exit code mismatch on fuzz round {i} (has_meta={has_meta}).\n"
                f"Oracle exit code: {oracle_res.returncode}\n"
                f"Agent exit code: {agent_res.returncode}"
            )
            assert agent_res.stdout == oracle_res.stdout, (
                f"Stdout mismatch on fuzz round {i} (has_meta={has_meta}).\n"
                f"Oracle stdout: {oracle_res.stdout!r}\n"
                f"Agent stdout: {agent_res.stdout!r}"
            )
            assert agent_res.stderr == oracle_res.stderr, (
                f"Stderr mismatch on fuzz round {i} (has_meta={has_meta}).\n"
                f"Oracle stderr: {oracle_res.stderr!r}\n"
                f"Agent stderr: {agent_res.stderr!r}"
            )
            assert not os.path.exists(ORACLE), "Agent recreated the legacy oracle path"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
