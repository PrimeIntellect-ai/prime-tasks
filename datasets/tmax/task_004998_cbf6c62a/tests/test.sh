#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

CRACKER = "/home/user/cracker.c"
RECOVERED = "/home/user/recovered_password.txt"
NEW_CREDENTIAL = "/home/user/new_credential.txt"
TARGET = 0x02E99F19


def custom_hash(text):
    value = 0x1337
    for byte in text.encode("ascii"):
        value = (((value << 5) + value + byte) & 0xffffffff) ^ 0xBEEF
    return value & 0xffffffff


def test_cracker_c_exists():
    path = CRACKER
    assert os.path.isfile(path), f"The file {path} is missing. You must write the C program."


def test_recovered_password():
    path = RECOVERED
    assert os.path.isfile(path), f"The file {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "proxy", f"The recovered password in {path} is incorrect. Expected 'proxy', got '{content}'."
    assert re.fullmatch(r"[a-z]{5}", content), "Recovered password must be five lowercase letters."
    assert custom_hash(content) == TARGET, "Recovered password does not produce the requested hash."


def test_new_credential():
    path = NEW_CREDENTIAL
    assert os.path.isfile(path), f"The file {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "0x78ab5a78", f"The new credential in {path} is incorrect. Expected '0x78ab5a78', got '{content}'."
    expected = f"0x{custom_hash('securekey'):x}"
    assert content == expected, "New credential was not computed with the custom hash algorithm."


def compile_source(source, output):
    result = subprocess.run(
        ["gcc", "-O2", "-std=c11", source, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"cracker.c does not compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK), "Compilation did not produce an executable."


def run_as_user(executable):
    uid = 1000
    gid = 1000
    try:
        import pwd
        entry = pwd.getpwnam("user")
        uid, gid = entry.pw_uid, entry.pw_gid
    except KeyError:
        pass

    def demote():
        os.setgid(gid)
        os.setuid(uid)

    env = {"PATH": "/usr/bin:/bin", "HOME": "/home/user", "LANG": "C"}
    return subprocess.run(
        [executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        env=env,
        cwd="/home/user",
        preexec_fn=demote,
    )


def candidate_from_run(result):
    candidates = re.findall(r"(?<![a-z])[a-z]{5}(?![a-z])", result.stdout + "\n" + result.stderr)
    if os.path.isfile(RECOVERED):
        with open(RECOVERED, "r", errors="replace") as f:
            value = f.read().strip()
        if re.fullmatch(r"[a-z]{5}", value):
            candidates.append(value)
    return candidates


def replace_target_literal(source, replacement):
    number = re.compile(r"(?<![A-Za-z0-9_.])(?:0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*")
    replaced = 0

    def convert(match):
        nonlocal replaced
        token = match.group(0)
        bare = re.sub(r"[uUlL]+$", "", token)
        try:
            value = int(bare, 0)
        except ValueError:
            return token
        if value == TARGET:
            replaced += 1
            return f"0x{replacement:x}u"
        return token

    result = number.sub(convert, source)
    assert replaced > 0, "cracker.c must contain the requested target hash so its brute-force implementation can be tested."
    return result


def test_compiled_cracker_really_bruteforces():
    with open(CRACKER, "r", errors="replace") as f:
        source = f.read()
    assert source.strip(), "cracker.c is empty."

    lowered = source.lower()
    assert "proxy" not in lowered, "cracker.c must recover the password rather than embed it."
    assert "0x78ab5a78" not in lowered, "cracker.c must compute the new hash rather than embed it."
    for forbidden in ("legacy_auth", "system(", "popen(", "execl(", "execv(", "posix_spawn("):
        assert forbidden not in lowered, "cracker.c must implement the algorithm itself and may not invoke legacy_auth."

    saved = {}
    for path in (RECOVERED, NEW_CREDENTIAL):
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()

    work = tempfile.mkdtemp(prefix="verify-cracker-")
    os.chmod(work, 0o755)
    try:
        original_exe = os.path.join(work, "cracker")
        compile_source(CRACKER, original_exe)
        os.chmod(original_exe, 0o755)
        if os.path.exists(RECOVERED):
            os.unlink(RECOVERED)
        result = run_as_user(original_exe)
        assert result.returncode == 0, f"Compiled cracker failed when run: {result.stderr}"
        candidates = candidate_from_run(result)
        assert any(custom_hash(x) == TARGET for x in candidates), "Running cracker.c did not recover a password for the requested target."

        alternate_password = "aaaaa"
        alternate_target = custom_hash(alternate_password)
        mutated = replace_target_literal(source, alternate_target)
        mutated_source = os.path.join(work, "cracker_alternate.c")
        with open(mutated_source, "w") as f:
            f.write(mutated)
        os.chmod(mutated_source, 0o644)
        alternate_exe = os.path.join(work, "cracker_alternate")
        compile_source(mutated_source, alternate_exe)
        os.chmod(alternate_exe, 0o755)
        if os.path.exists(RECOVERED):
            os.unlink(RECOVERED)
        result = run_as_user(alternate_exe)
        assert result.returncode == 0, f"Cracker failed on an alternate verifier-derived target: {result.stderr}"
        candidates = candidate_from_run(result)
        assert any(custom_hash(x) == alternate_target for x in candidates), "cracker.c embeds the known answer instead of brute-forcing its target hash."
    finally:
        for path in (RECOVERED, NEW_CREDENTIAL):
            if path in saved:
                with open(path, "wb") as f:
                    f.write(saved[path])
            elif os.path.exists(path):
                os.unlink(path)
        shutil.rmtree(work, ignore_errors=True)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
