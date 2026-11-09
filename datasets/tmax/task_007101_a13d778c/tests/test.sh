#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shlex
import shutil
import subprocess
import tempfile

APP = "/home/user/web-app"
EXPECTED_QUERY = "user=bob&role=admin"
EXPECTED_OUTPUT = '{"user":"bob","role":"admin"}'


def run_as_user(cmd, cwd):
    """Run a command as 'user' if currently root, otherwise run normally."""
    current_user = pwd.getpwuid(os.getuid()).pw_name
    if current_user == "user":
        return subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, timeout=30)
    return subprocess.run(
        ["su", "user", "-c", f"cd {shlex.quote(cwd)} && {cmd}"],
        capture_output=True,
        timeout=30,
    )


def test_fix_patch_exists_and_valid():
    patch_file = os.path.join(APP, "fix.patch")
    original = os.path.join(APP, "Makefile.orig")
    makefile = os.path.join(APP, "Makefile")
    assert os.path.isfile(patch_file), f"Patch file {patch_file} is missing."

    with open(patch_file, "rb") as f:
        patch_bytes = f.read()
    content = patch_bytes.decode()

    # Preserve the original assertions.
    assert "json_serializer.o" in content, (
        "The patch file does not appear to add json_serializer.o to the Makefile."
    )
    assert "---" in content and "+++" in content, (
        "The patch file does not look like a unified diff."
    )

    # The submitted patch must be the actual unified diff of the backup and
    # current Makefile, rather than merely containing diff-like text.
    generated = subprocess.run(
        ["diff", "-u", "Makefile.orig", "Makefile"],
        cwd=APP,
        capture_output=True,
        timeout=10,
    )
    assert generated.returncode == 1, "Makefile was not changed from Makefile.orig."
    assert patch_bytes == generated.stdout, (
        "fix.patch is not the unified diff of Makefile.orig and Makefile."
    )

    # Independently verify that the patch applies to the original and recreates
    # the submitted Makefile.
    with tempfile.TemporaryDirectory() as td:
        base = os.path.join(td, "Makefile.orig")
        shutil.copyfile(original, base)
        applied = subprocess.run(
            ["patch", "--batch", "Makefile.orig"],
            cwd=td,
            input=patch_bytes,
            capture_output=True,
            timeout=10,
        )
        assert applied.returncode == 0, (
            "fix.patch does not apply cleanly to Makefile.orig.\n"
            f"Stdout: {applied.stdout.decode()}\nStderr: {applied.stderr.decode()}"
        )
        with open(base, "rb") as f:
            patched_bytes = f.read()
        with open(makefile, "rb") as f:
            makefile_bytes = f.read()
        assert patched_bytes == makefile_bytes, (
            "Applying fix.patch to Makefile.orig does not recreate Makefile."
        )


def test_makefile_independently_builds_and_binary_output_is_correct():
    result = run_as_user("make clean && make", APP)
    assert result.returncode == 0, (
        "The verifier could not independently build the project.\n"
        f"Stdout: {result.stdout.decode()}\nStderr: {result.stderr.decode()}"
    )

    binary = os.path.join(APP, "cgi_bin")
    assert os.path.isfile(binary), "make did not create cgi_bin."
    assert os.access(binary, os.X_OK), "cgi_bin is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cgi_bin is not a compiled ELF executable."

    result = run_as_user(f"./cgi_bin {shlex.quote(EXPECTED_QUERY)}", APP)
    assert result.returncode == 0, (
        f"cgi_bin exited with status {result.returncode}. Stderr: {result.stderr.decode()}"
    )
    assert result.stdout.decode() == EXPECTED_OUTPUT, (
        "cgi_bin produced incorrect output for the required query. "
        f"Got: {result.stdout.decode()!r}"
    )


def test_ci_test_executable():
    ci_script = os.path.join(APP, "ci_test.sh")
    assert os.path.isfile(ci_script), f"CI script {ci_script} is missing."
    assert os.access(ci_script, os.X_OK), f"CI script {ci_script} is not executable."


def test_ci_test_success():
    result = run_as_user("./ci_test.sh", APP)
    assert result.returncode == 0, (
        "ci_test.sh failed when it should have succeeded.\n"
        f"Stdout: {result.stdout.decode()}\n"
        f"Stderr: {result.stderr.decode()}"
    )


def test_ci_script_runs_make_and_executes_binary_with_exact_argument():
    # Put an instrumented make first in PATH. Its build step creates an
    # instrumented cgi_bin, allowing the verifier to observe both required make
    # invocations and the exact argument passed to the binary.
    with tempfile.TemporaryDirectory() as td:
        os.chmod(td, 0o777)
        make_log = os.path.join(td, "make.log")
        argc_log = os.path.join(td, "argc.log")
        arg_log = os.path.join(td, "arg.log")
        fake_make = os.path.join(td, "make")

        with open(fake_make, "w") as f:
            f.write(f"""#!/bin/sh
if [ \"$#\" -eq 0 ]; then
    printf '%s\\n' '<default>' >> {shlex.quote(make_log)}
    cat > ./cgi_bin <<'BIN_EOF'
#!/bin/sh
printf '%s\\n' \"$#\" > {argc_log}
printf '%s' \"${{1-}}\" > {arg_log}
printf '%s' '{EXPECTED_OUTPUT}'
BIN_EOF
    chmod +x ./cgi_bin
    exit 0
fi
printf '%s\\n' \"$*\" >> {shlex.quote(make_log)}
[ \"$#\" -eq 1 ] && [ \"$1\" = clean ] && exit 0
exit 2
""")
        os.chmod(fake_make, 0o755)

        result = run_as_user(
            f"PATH={shlex.quote(td)}:/usr/bin:/bin ./ci_test.sh",
            APP,
        )
        assert result.returncode == 0, (
            "ci_test.sh did not succeed with a successful instrumented build and binary.\n"
            f"Stdout: {result.stdout.decode()}\nStderr: {result.stderr.decode()}"
        )

        with open(make_log) as f:
            calls = [line.rstrip("\n") for line in f]
        assert "clean" in calls, "ci_test.sh did not run make clean."
        assert "<default>" in calls, "ci_test.sh did not run make."
        assert os.path.isfile(argc_log), "ci_test.sh did not execute the built ./cgi_bin."
        with open(argc_log) as f:
            assert f.read().strip() == "1", "ci_test.sh passed the wrong number of arguments."
        with open(arg_log) as f:
            assert f.read() == EXPECTED_QUERY, (
                "ci_test.sh did not pass the exact required query to ./cgi_bin."
            )


def test_ci_test_failure_on_bad_output():
    main_c = os.path.join(APP, "main.c")
    backup_main_c = os.path.join(APP, "main.c.bak")
    shutil.copy(main_c, backup_main_c)

    try:
        bad_main = """#include <stdio.h>
int main() {
    printf("BAD OUTPUT");
    return 0;
}
"""
        with open(main_c, "w") as f:
            f.write(bad_main)

        result = run_as_user("./ci_test.sh", APP)
        assert result.returncode == 1, (
            "ci_test.sh should exit with code 1 when the application output does not match "
            f"the expected JSON. It exited with code {result.returncode} instead."
        )
    finally:
        shutil.move(backup_main_c, main_c)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
