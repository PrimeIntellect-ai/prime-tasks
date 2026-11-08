#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import shutil
import string
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
TOKEN_GEN_CPP = os.path.join(WORKSPACE_DIR, "token_gen.cpp")
TOKEN_GEN = os.path.join(WORKSPACE_DIR, "token_gen")
NEW_TOKEN_TXT = os.path.join(WORKSPACE_DIR, "new_token.txt")
VERIFY_SH = os.path.join(WORKSPACE_DIR, "verify.sh")
UNSHARE = "/usr/bin/unshare"
SECRET = "r0t4t10n_M4st3r_99"
DATE = "20241231"


def expected_token(secret, date):
    return "".join(f"{ord(ch) ^ ord(date[i % len(date)]):02x}" for i, ch in enumerate(secret))


def run_generator(executable, secret, date):
    result = subprocess.run(
        [executable, secret, date],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed for secret/date input with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert result.stdout.strip() == expected_token(secret, date), (
        f"{executable} produced an incorrect token for a verifier-generated input."
    )


def generated_cases():
    alphabet = string.ascii_letters + string.digits + "_-!@#"
    cases = [("a", "1"), ("longer_secret_for_cycling", "42")]
    for _ in range(6):
        secret = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(35) + 1))
        date = "".join(secrets.choice(string.digits) for _ in range(secrets.randbelow(11) + 1))
        cases.append((secret, date))
    return cases


def test_token_gen_cpp_exists_and_implements_algorithm():
    assert os.path.isfile(TOKEN_GEN_CPP), f"File {TOKEN_GEN_CPP} is missing."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "token_gen_rebuilt")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", TOKEN_GEN_CPP, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"{TOKEN_GEN_CPP} does not compile.\nStdout: {compile_result.stdout}\n"
            f"Stderr: {compile_result.stderr}"
        )
        for secret, date in generated_cases():
            run_generator(rebuilt, secret, date)


def test_compiled_token_gen_exists_and_implements_algorithm():
    assert os.path.isfile(TOKEN_GEN), f"Compiled program {TOKEN_GEN} is missing."
    assert os.access(TOKEN_GEN, os.X_OK), f"Compiled program {TOKEN_GEN} is not executable."
    with open(TOKEN_GEN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{TOKEN_GEN} is not an ELF executable."
    for secret, date in generated_cases():
        run_generator(TOKEN_GEN, secret, date)


def test_new_token_txt_content():
    assert os.path.isfile(NEW_TOKEN_TXT), f"File {NEW_TOKEN_TXT} is missing."
    with open(NEW_TOKEN_TXT, "r") as f:
        content = f.read().strip()
    expected_hex = expected_token(SECRET, DATE)
    assert content == expected_hex, (
        f"Content of {NEW_TOKEN_TXT} is incorrect. Expected '{expected_hex}', got '{content}'."
    )


def test_verify_sh_exists_and_executable():
    assert os.path.isfile(VERIFY_SH), f"File {VERIFY_SH} is missing."
    assert os.access(VERIFY_SH, os.X_OK), f"File {VERIFY_SH} is not executable."


def test_verify_sh_contents():
    with open(VERIFY_SH, "r") as f:
        content = f.read()
    assert "unshare" in content, f"{VERIFY_SH} does not use the 'unshare' utility."
    assert "--net" in content, f"{VERIFY_SH} does not use the '--net' flag for network namespace isolation."
    assert "--ipc" in content, f"{VERIFY_SH} does not use the '--ipc' flag for IPC namespace isolation."
    assert "auth_service" in content, f"{VERIFY_SH} does not appear to execute the 'auth_service' binary."


def test_verify_sh_execution():
    result = subprocess.run(
        [VERIFY_SH], cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Execution of {VERIFY_SH} failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_verify_sh_really_invokes_unshare_with_required_command():
    assert os.path.isfile(UNSHARE), f"Standard unshare utility {UNSHARE} is missing."
    nonce = secrets.token_hex(8)
    backup = f"/tmp/unshare.real.{nonce}"
    log = pathlib.Path(f"/tmp/unshare.args.{nonce}")

    os.replace(UNSHARE, backup)
    try:
        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\0' \"$@\" > {str(log)!r}\n"
            f"exec {backup!r} \"$@\"\n"
        )
        pathlib.Path(UNSHARE).write_text(wrapper)
        os.chmod(UNSHARE, 0o755)

        result = subprocess.run(
            [VERIFY_SH], cwd=WORKSPACE_DIR, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"Execution of {VERIFY_SH} failed while tracing unshare.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert log.is_file(), f"{VERIFY_SH} did not actually invoke the standard unshare utility."
        raw_args = log.read_bytes().split(b"\0")
        args = [arg.decode("utf-8", "surrogateescape") for arg in raw_args if arg]

        assert "--net" in args, "verify.sh did not pass --net as an argument to unshare."
        assert "--ipc" in args, "verify.sh did not pass --ipc as an argument to unshare."

        auth_candidates = {"./auth_service", os.path.join(WORKSPACE_DIR, "auth_service")}
        auth_indexes = [i for i, arg in enumerate(args) if arg in auth_candidates]
        assert auth_indexes, (
            "verify.sh did not ask unshare to execute ./auth_service; "
            f"captured unshare arguments were {args!r}."
        )
        index = auth_indexes[0]
        assert args.index("--net") < index and args.index("--ipc") < index, (
            "The namespace flags must be unshare options preceding auth_service."
        )
        assert index + 1 < len(args), "verify.sh did not pass a token to auth_service."
        assert args[index + 1] == expected_token(SECRET, DATE), (
            "verify.sh did not pass the contents of new_token.txt to auth_service."
        )
    finally:
        try:
            if os.path.lexists(UNSHARE):
                os.unlink(UNSHARE)
        finally:
            if os.path.exists(backup):
                os.replace(backup, UNSHARE)
        try:
            log.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
