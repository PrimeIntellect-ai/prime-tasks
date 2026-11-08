#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shlex
import secrets
import subprocess
import tempfile
import pytest

UPLOADER_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <PIN> <filename>\n", argv[0]);
        return 1;
    }

    int pin = atoi(argv[1]);
    // The secret PIN is 7392
    if (pin != 7392) {
        printf("Authentication failed.\n");
        return 1;
    }

    char filepath[256];
    snprintf(filepath, sizeof(filepath), "/home/user/sandbox/%s", argv[2]);

    FILE *f = fopen(filepath, "r");
    if (!f) {
        printf("Error: Could not read file %s\n", filepath);
        return 1;
    }

    char buffer[256];
    printf("File contents:\n");
    while (fgets(buffer, sizeof(buffer), f) != NULL) {
        printf("%s", buffer);
    }
    fclose(f);
    return 0;
}
'''


def assert_original_uploader():
    path = "/home/user/vuln_uploader"
    assert os.path.isfile(path), f"The original binary {path} was removed or missing."
    assert os.access(path, os.X_OK), f"The original binary {path} is no longer executable."

    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "vuln_uploader.c")
        expected = os.path.join(td, "vuln_uploader")
        with open(source, "w") as f:
            f.write(UPLOADER_SOURCE)
        subprocess.run(["gcc", source, "-o", expected], check=True, timeout=30)
        with open(path, "rb") as actual_file, open(expected, "rb") as expected_file:
            assert actual_file.read() == expected_file.read(), (
                "The original /home/user/vuln_uploader binary was modified."
            )


@pytest.fixture(scope="session", autouse=True)
def compile_and_execute_submission():
    source = "/home/user/audit_exploit.c"
    executable = "/home/user/audit_exploit"
    report = "/home/user/audit_report.log"
    uploader = "/home/user/vuln_uploader"
    flag_path = "/home/user/restricted/flag.txt"

    assert os.path.isfile(source), f"Expected C source file {source} does not exist."
    assert stat.S_ISREG(os.stat(source, follow_symlinks=False).st_mode), (
        f"Expected {source} to be a regular C source file."
    )
    assert_original_uploader()

    dynamic_flag = f"FLAG{{audit_{secrets.token_hex(16)}}}"
    with open(flag_path, "w") as f:
        f.write(dynamic_flag + "\n")

    for stale in (executable, report):
        if os.path.lexists(stale):
            os.remove(stale)

    subprocess.run(
        ["gcc", source, "-o", executable],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)

    with tempfile.TemporaryDirectory() as td:
        original = os.path.join(td, "vuln_uploader.original")
        count_marker = os.path.join(td, "argc")
        pin_marker = os.path.join(td, "pin")
        filename_marker = os.path.join(td, "filename")

        os.replace(uploader, original)
        wrapper = f'''#!/bin/sh
printf '%s' "$#" > {shlex.quote(count_marker)}
if [ "$#" -ge 1 ]; then printf '%s' "$1" > {shlex.quote(pin_marker)}; fi
if [ "$#" -ge 2 ]; then printf '%s' "$2" > {shlex.quote(filename_marker)}; fi
exec {shlex.quote(original)} "$@"
'''
        with open(uploader, "w") as f:
            f.write(wrapper)
        os.chmod(uploader, 0o755)

        try:
            result = subprocess.run(
                [executable],
                cwd="/home/user",
                timeout=30,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        finally:
            if os.path.lexists(uploader):
                os.remove(uploader)
            os.replace(original, uploader)

        assert result.returncode == 0, (
            f"The compiled exploit exited with status {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(count_marker), (
            "The exploit did not invoke /home/user/vuln_uploader."
        )
        with open(count_marker) as f:
            assert f.read() == "2", "vuln_uploader was not invoked with exactly two arguments."
        with open(pin_marker) as f:
            assert f.read() == "7392", "The exploit did not pass the valid PIN."
        with open(filename_marker) as f:
            filename = f.read()
        resolved = os.path.normpath(os.path.join("/home/user/sandbox", filename))
        assert resolved == flag_path, (
            "The exploit did not pass a traversal filename resolving from the sandbox "
            "to /home/user/restricted/flag.txt."
        )
        assert ".." in filename.split("/"), "The filename argument did not use path traversal."

    assert_original_uploader()
    yield


def test_audit_exploit_c_exists():
    path = "/home/user/audit_exploit.c"
    assert os.path.isfile(path), f"Expected C source file {path} does not exist."


def test_audit_report_log_content():
    log_path = "/home/user/audit_report.log"
    flag_path = "/home/user/restricted/flag.txt"

    assert os.path.isfile(log_path), f"The audit report {log_path} was not created."
    assert os.path.isfile(flag_path), f"The flag file {flag_path} is missing."

    with open(flag_path, "r") as f:
        flag_content = f.read().strip()

    expected_content = f"[AUDIT_TRAIL] VULNERABILITY_CONFIRMED: {flag_content}"

    with open(log_path, "r") as f:
        log_content = f.read().strip()

    assert log_content == expected_content, (
        f"The content of {log_path} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{log_content}'"
    )


def test_vuln_uploader_unmodified():
    assert_original_uploader()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
