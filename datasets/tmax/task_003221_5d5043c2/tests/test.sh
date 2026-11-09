#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile

BASE = "/home/user/mail_spool"
PROGRAM = "/home/user/setup_spool"
SOURCE = "/home/user/setup_spool.c"
DIRECTORIES = [
    BASE,
    BASE + "/inbox",
    BASE + "/outbox",
    BASE + "/archive",
]
EXPECTED_TARGET = "/usr/share/zoneinfo/Europe/Paris"
EXPECTED_CONTENT = "MAILING_LIST_TZ=Europe/Paris\nLC_TIME=fr_FR.UTF-8\n"


def run_program(path):
    result = subprocess.run([path], capture_output=True, timeout=15)
    assert result.returncode == 0, (
        f"Execution of {path} failed with return code {result.returncode}. "
        f"Stderr: {result.stderr.decode(errors='replace')}"
    )


def verify_state():
    for directory in DIRECTORIES:
        assert os.path.isdir(directory), f"Directory {directory} does not exist."
        perms = stat.S_IMODE(os.stat(directory).st_mode)
        assert perms == 0o750, (
            f"Directory {directory} has incorrect permissions: "
            f"{oct(perms)}, expected 0o750."
        )

    symlink_path = BASE + "/tz_local"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target == EXPECTED_TARGET, (
        f"Symlink points to {target}, expected {EXPECTED_TARGET}."
    )

    conf_path = BASE + "/mailer.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."
    perms = stat.S_IMODE(os.stat(conf_path).st_mode)
    assert perms == 0o640, (
        f"File {conf_path} has incorrect permissions: {oct(perms)}, expected 0o640."
    )

    with open(conf_path, "r") as conf:
        content = conf.read()

    lines = content.splitlines()
    assert len(lines) == 2, (
        f"Expected exactly 2 lines in {conf_path}, found {len(lines)}."
    )
    assert lines[0] == "MAILING_LIST_TZ=Europe/Paris", (
        f"First line is '{lines[0]}', expected 'MAILING_LIST_TZ=Europe/Paris'."
    )
    assert lines[1] == "LC_TIME=fr_FR.UTF-8", (
        f"Second line is '{lines[1]}', expected 'LC_TIME=fr_FR.UTF-8'."
    )
    assert content.endswith("\n"), (
        f"{conf_path} does not end with a newline character."
    )
    assert content == EXPECTED_CONTENT, f"{conf_path} has unexpected content."


def state_signature():
    return (
        tuple(stat.S_IMODE(os.stat(path).st_mode) for path in DIRECTORIES),
        os.readlink(BASE + "/tz_local"),
        stat.S_IMODE(os.stat(BASE + "/mailer.conf").st_mode),
        open(BASE + "/mailer.conf", "rb").read(),
    )


def corrupt_state():
    # Damage every kind of managed state so a no-op executable cannot pass.
    for directory in DIRECTORIES:
        if os.path.isdir(directory):
            os.chmod(directory, 0o777)

    archive = BASE + "/archive"
    if os.path.isdir(archive):
        os.rmdir(archive)

    tz_path = BASE + "/tz_local"
    if os.path.lexists(tz_path):
        os.unlink(tz_path)
    os.symlink("/usr/share/zoneinfo/UTC", tz_path)

    conf_path = BASE + "/mailer.conf"
    if os.path.lexists(conf_path):
        os.unlink(conf_path)
    with open(conf_path, "w") as conf:
        conf.write("BROKEN=1\n")
    os.chmod(conf_path, 0o666)


def test_compiled_program_and_idempotent_setup():
    # Preserve the original existence and executability assertions.
    assert os.path.exists(PROGRAM), f"{PROGRAM} does not exist."
    assert os.access(PROGRAM, os.X_OK), f"{PROGRAM} is not executable."
    assert os.path.isfile(PROGRAM) and not os.path.islink(PROGRAM), (
        f"{PROGRAM} must be a regular executable file."
    )

    # Reject shell scripts and other trivial executable placeholders.
    with open(PROGRAM, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", (
            f"{PROGRAM} is not a compiled ELF executable."
        )

    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), (
        f"{SOURCE} does not exist or is not a regular C source file."
    )

    # Independently compile the submitted C source with gcc and later exercise it.
    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "setup_spool")
        build = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], capture_output=True, timeout=30
        )
        assert build.returncode == 0, (
            "The submitted C source does not compile with gcc. Stderr: "
            + build.stderr.decode(errors="replace")
        )

        # Start with no pre-created target state: the submitted executable must
        # create all of it rather than relying on the agent's final filesystem.
        if os.path.lexists(BASE):
            if os.path.isdir(BASE) and not os.path.islink(BASE):
                shutil.rmtree(BASE)
            else:
                os.unlink(BASE)
        run_program(PROGRAM)
        verify_state()

        # Damage the managed state and require the submitted executable to repair it.
        corrupt_state()
        run_program(PROGRAM)
        verify_state()

        # A consecutive run must succeed and preserve the exact specified state.
        before = state_signature()
        run_program(PROGRAM)
        verify_state()
        assert state_signature() == before, (
            "A consecutive execution changed the specified target state."
        )

        # The independently rebuilt submitted C source must implement the same setup.
        corrupt_state()
        run_program(rebuilt)
        verify_state()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
