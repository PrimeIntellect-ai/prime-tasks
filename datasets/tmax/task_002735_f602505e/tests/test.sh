#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess

C_FILE = "/home/user/provision.c"
BIN_FILE = "/home/user/provision_bin"
LOG_FILE = "/home/user/provision.log"
COUNT_FILE = "/home/user/.fail_count"
SCRIPT_FILE = "/home/user/flaky_qemu.sh"

EXPECTED_SCRIPT = b'''#!/bin/bash
COUNT_FILE="/home/user/.fail_count"
if [ ! -f "$COUNT_FILE" ]; then
    echo 1 > "$COUNT_FILE"
    exit 1
fi
COUNT=$(cat "$COUNT_FILE")
if [ "$COUNT" -lt 3 ]; then
    echo $((COUNT + 1)) > "$COUNT_FILE"
    exit 1
else
    exit 0
fi
'''


def test_provision_c_exists():
    assert os.path.isfile(C_FILE), f"Expected C source file {C_FILE} does not exist."


def test_provision_bin_exists_and_executable():
    assert os.path.isfile(BIN_FILE), f"Expected executable {BIN_FILE} does not exist."
    st = os.stat(BIN_FILE)
    assert st.st_mode & stat.S_IXUSR, f"{BIN_FILE} is not executable."
    with open(BIN_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN_FILE} is not a compiled ELF executable."


def test_provision_log_content():
    assert os.path.isfile(LOG_FILE), f"Expected log file {LOG_FILE} does not exist. Did you run the compiled program?"
    with open(LOG_FILE, "r") as f:
        actual_lines = [line for line in f.read().splitlines() if line]

    expected_lines = [
        "Provisioning Restart",
        "Provisioning Restart",
        "Provisioning Restart",
        "Provisioning Success",
    ]
    assert actual_lines == expected_lines, (
        "Log file content does not match the result of running the supplied flaky script "
        "from its initial state.\nExpected:\n"
        + "\n".join(expected_lines)
        + "\nActual:\n"
        + "\n".join(actual_lines)
    )


def test_submitted_program_behavior():
    assert os.path.isfile(SCRIPT_FILE)
    with open(SCRIPT_FILE, "rb") as f:
        original_script = f.read()
    original_mode = stat.S_IMODE(os.stat(SCRIPT_FILE).st_mode)
    assert original_script == EXPECTED_SCRIPT, "The supplied flaky_qemu.sh was modified."
    assert original_mode & stat.S_IXUSR, "The supplied flaky_qemu.sh is no longer executable."

    built_from_source = "/tmp/provision_from_source"
    compiled = subprocess.run(
        ["gcc", C_FILE, "-o", built_from_source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compiled.returncode == 0, f"provision.c did not compile:\n{compiled.stderr}"

    def restore_script():
        with open(SCRIPT_FILE, "wb") as f:
            f.write(EXPECTED_SCRIPT)
        os.chmod(SCRIPT_FILE, original_mode)

    def remove_state():
        for path in (LOG_FILE, COUNT_FILE, "/home/user/.verifier_attempt_count"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    def run_program(program, env=None):
        if env is None:
            env = os.environ.copy()
            env["VM_QUOTA_DIR"] = "/home/user"
        return subprocess.run(
            [program],
            env=env,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )

    try:
        for program in (BIN_FILE, built_from_source):
            # The supplied script fails three times and succeeds on attempt four.
            restore_script()
            remove_state()
            result = run_program(program)
            assert result.returncode == 0, f"{program} did not succeed on the fourth attempt."
            with open(LOG_FILE, "r") as f:
                assert f.read() == (
                    "Provisioning Restart\n"
                    "Provisioning Restart\n"
                    "Provisioning Restart\n"
                    "Provisioning Success\n"
                )
            with open(COUNT_FILE, "r") as f:
                assert f.read().strip() == "3"

            # An unset VM_QUOTA_DIR must cause an immediate status-2 exit.
            restore_script()
            remove_state()
            env = os.environ.copy()
            env.pop("VM_QUOTA_DIR", None)
            result = run_program(program, env)
            assert result.returncode == 2, f"{program} did not exit 2 when VM_QUOTA_DIR was unset."
            assert not os.path.exists(LOG_FILE), "The program wrote the log before validating VM_QUOTA_DIR."
            assert not os.path.exists(COUNT_FILE), "The program executed the script with VM_QUOTA_DIR unset."

            # Existing log content must be preserved because messages are appended.
            restore_script()
            remove_state()
            with open(COUNT_FILE, "w") as f:
                f.write("3\n")
            with open(LOG_FILE, "w") as f:
                f.write("Existing Entry\n")
            result = run_program(program)
            assert result.returncode == 0
            with open(LOG_FILE, "r") as f:
                assert f.read() == "Existing Entry\nProvisioning Success\n"

        # Force statvfs to report zero available bytes and test the freshly
        # compiled source artifact, which is dynamically linked by gcc here.
        mock_source = "/tmp/mock_statvfs.c"
        mock_library = "/tmp/mock_statvfs.so"
        with open(mock_source, "w") as f:
            f.write(r'''#include <sys/statvfs.h>
#include <string.h>
int statvfs(const char *path, struct statvfs *buf) {
    (void)path;
    memset(buf, 0, sizeof(*buf));
    buf->f_frsize = 4096;
    buf->f_bavail = 0;
    return 0;
}
''')
        mock_build = subprocess.run(
            ["gcc", "-shared", "-fPIC", mock_source, "-o", mock_library],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert mock_build.returncode == 0, mock_build.stderr

        restore_script()
        remove_state()
        env = os.environ.copy()
        env["VM_QUOTA_DIR"] = "/home/user"
        env["LD_PRELOAD"] = mock_library
        result = run_program(built_from_source, env)
        assert result.returncode == 2, "Program did not exit 2 when statvfs reported less than 1024 bytes."
        assert not os.path.exists(LOG_FILE), "Program wrote the log despite insufficient space."
        assert not os.path.exists(COUNT_FILE), "Program executed the script despite insufficient space."

        # Exercise the exhausted-retry path with a script that always fails.
        failing_script = b'''#!/bin/bash
COUNT_FILE="/home/user/.verifier_attempt_count"
COUNT=0
if [ -f "$COUNT_FILE" ]; then COUNT=$(cat "$COUNT_FILE"); fi
echo $((COUNT + 1)) > "$COUNT_FILE"
exit 1
'''
        for program in (BIN_FILE, built_from_source):
            remove_state()
            with open(SCRIPT_FILE, "wb") as f:
                f.write(failing_script)
            os.chmod(SCRIPT_FILE, 0o755)
            result = run_program(program)
            assert result.returncode == 1, f"{program} did not exit 1 after four failed attempts."
            with open("/home/user/.verifier_attempt_count", "r") as f:
                assert f.read().strip() == "4", f"{program} did not stop after four executions."
            with open(LOG_FILE, "r") as f:
                lines = f.read().splitlines()
            assert lines[-1:] == ["Provisioning Failed"]
            assert all(line == "Provisioning Restart" for line in lines[:-1])
            assert len(lines[:-1]) in (3, 4)
    finally:
        with open(SCRIPT_FILE, "wb") as f:
            f.write(original_script)
        os.chmod(SCRIPT_FILE, original_mode)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
