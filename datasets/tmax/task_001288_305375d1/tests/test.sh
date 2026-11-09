#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import stat
import string
import subprocess


def test_asset_counts():
    path = "/home/user/asset_counts.txt"
    assert os.path.exists(path), f"Missing required file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "154,240"
    assert content == expected, f"Expected '{expected}' in {path}, but got '{content}'"


def _copy_executable_and_libraries(source, destination, root):
    if not os.path.exists(source):
        return

    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.copy2(os.path.realpath(source), destination)
    os.chmod(destination, 0o755)

    result = subprocess.run(["ldd", os.path.realpath(source)], capture_output=True, text=True, check=True)
    libraries = set()
    for line in result.stdout.splitlines():
        fields = line.strip().split()
        if "=>" in fields:
            candidate = fields[fields.index("=>") + 1]
            if candidate.startswith("/"):
                libraries.add(candidate)
        elif fields and fields[0].startswith("/"):
            libraries.add(fields[0])

    for library in libraries:
        target = os.path.join(root, library.lstrip("/"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.realpath(library), target)


def _build_sandbox(agent_script):
    root = "/tmp/decode-sandbox"
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(os.path.join(root, "submission"), mode=0o755)

    sandbox_script = os.path.join(root, "submission", "decode.sh")
    shutil.copy2(agent_script, sandbox_script)
    os.chmod(sandbox_script, 0o444)

    # Supply the shell, awk, and ordinary text/number-processing utilities a
    # Bash implementation may reasonably use. The agent's filesystem and the
    # reference decoder are deliberately not present in this chroot.
    executables = [
        ("/bin/bash", "/bin/bash"),
        ("/usr/bin/awk", "/usr/bin/awk"),
        ("/usr/bin/gawk", "/usr/bin/gawk"),
        ("/usr/bin/mawk", "/usr/bin/mawk"),
        ("/usr/bin/sed", "/usr/bin/sed"),
        ("/usr/bin/cut", "/usr/bin/cut"),
        ("/usr/bin/tr", "/usr/bin/tr"),
        ("/usr/bin/od", "/usr/bin/od"),
        ("/usr/bin/xxd", "/usr/bin/xxd"),
        ("/usr/bin/printf", "/usr/bin/printf"),
        ("/usr/bin/bc", "/usr/bin/bc"),
    ]
    for source, destination in executables:
        _copy_executable_and_libraries(source, os.path.join(root, destination.lstrip("/")), root)

    # Everything in the sandbox is root-owned and read-only to the account
    # used for execution, preventing an embedded copied executable from being
    # materialized and run during a test.
    for directory, subdirs, files in os.walk(root):
        os.chown(directory, 0, 0)
        os.chmod(directory, 0o755)
        for name in files:
            path = os.path.join(directory, name)
            os.chown(path, 0, 0)
            current = stat.S_IMODE(os.stat(path).st_mode)
            os.chmod(path, 0o555 if current & 0o111 else 0o444)

    return root


def _expected(hex_string):
    total = ctypes.c_float(0.0)
    for offset in range(0, len(hex_string), 2):
        value = int(hex_string[offset:offset + 2], 16)
        total = ctypes.c_float(total.value + value)
    return f"{total.value / 3.0:.4f}\n"


def _run_submission(root, hex_string):
    return subprocess.run(
        [
            "/usr/sbin/chroot",
            "--userspec=65534:65534",
            root,
            "/bin/bash",
            "/submission/decode.sh",
            hex_string,
        ],
        capture_output=True,
        text=True,
        timeout=3,
        env={"PATH": "/bin:/usr/bin", "LC_ALL": "C"},
    )


def test_fuzz_equivalence():
    oracle_path = "/app/reference_decoder"
    agent_script = "/home/user/decode.sh"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle binary is not executable: {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert stat.S_ISREG(os.lstat(agent_script).st_mode), f"Submission must be a regular file: {agent_script}"

    with open(agent_script, "rb") as submission:
        source = submission.read()
    assert source, "decode.sh is empty"
    assert b"\x00" not in source and not source.startswith(b"\x7fELF"), "decode.sh must be a Bash source file"

    root = _build_sandbox(agent_script)

    alphabet = string.hexdigits[:16]
    cases = [
        "0", "F", "a", "00", "01", "ff", "ABC", "12345",
        "00" * 128, "FF" * 128, "0123456789abcdef" * 32,
        "FF" * 70000,
    ]
    cases.extend("A" * length for length in range(1, 34))

    # Use fresh, unpredictable cases and include odd lengths and short inputs,
    # rather than exposing a fixed even-length corpus that can be hard-coded.
    for _ in range(500):
        length = secrets.randbelow(2048) + 1
        cases.append("".join(secrets.choice(alphabet) for _ in range(length)))

    for index, hex_string in enumerate(cases, 1):
        result = _run_submission(root, hex_string)
        expected_stdout = _expected(hex_string)

        assert result.returncode == 0, (
            f"Return code mismatch on case {index}: expected 0, got {result.returncode}\n"
            f"stderr: {result.stderr}"
        )
        assert result.stdout == expected_stdout, (
            f"Standard output mismatch on case {index}, input length {len(hex_string)}.\n"
            f"Expected: {expected_stdout!r}\nGot: {result.stdout!r}"
        )
        assert result.stderr == "", (
            f"Standard error mismatch on case {index}: expected empty stderr, got {result.stderr!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
