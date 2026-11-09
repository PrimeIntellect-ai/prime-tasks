#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import subprocess
import tempfile


def test_env_var_txt():
    path = "/home/user/env_var.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "MALLOC_PERTURB_", f"Expected 'MALLOC_PERTURB_' in {path}, got '{content}'."


def test_trace_txt():
    path = "/home/user/trace.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "11", f"Expected '11' in {path}, got '{content}'."


def build_probe(directory, child_status, log_path):
    source_path = os.path.join(directory, f"probe_{child_status}.c")
    binary_path = os.path.join(directory, f"probe_{child_status}")
    source = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

int main(int argc, char **argv) {
    FILE *f = fopen("%s", "a");
    if (f) {
        const char *value = getenv("MALLOC_PERTURB_");
        fprintf(f, "ENV=%%s\tARGC=%%d\tARG1=%%s\n",
                value ? value : "<unset>", argc,
                argc > 1 ? argv[1] : "<missing>");
        fclose(f);
    }
    if (%d == 139) {
        raise(SIGSEGV);
        return 139;
    }
    return %d;
}
''' % (log_path, child_status, child_status)
    with open(source_path, "w") as f:
        f.write(source)
    subprocess.run(["gcc", "-o", binary_path, source_path], check=True)
    return binary_path


def test_regression_sh():
    path = "/home/user/regression.sh"
    parser = "/home/user/vuln_parser"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert os.path.isfile(parser), f"File {parser} does not exist."

    tempdir = tempfile.mkdtemp(prefix="regression_probe_")
    backup = os.path.join(tempdir, "vuln_parser.original")
    shutil.copy2(parser, backup)

    try:
        for child_status, expected_script_status in ((139, 0), (0, 1), (42, 1)):
            log_path = os.path.join(tempdir, f"calls_{child_status}.log")
            probe = build_probe(tempdir, child_status, log_path)
            shutil.copy2(probe, parser)
            os.chmod(parser, 0o755)

            result = subprocess.run([path], cwd="/home/user", capture_output=True)
            assert result.returncode == expected_script_status, (
                f"When vuln_parser returns status {child_status}, expected {path} "
                f"to exit with {expected_script_status}, but it exited with "
                f"{result.returncode}."
            )
            assert os.path.isfile(log_path), (
                "regression.sh did not execute /home/user/vuln_parser."
            )
            with open(log_path, "r") as f:
                calls = [line.rstrip("\n") for line in f]
            expected_call = "ENV=255\tARGC=2\tARG1=payload.bin"
            assert expected_call in calls, (
                "regression.sh must execute ./vuln_parser payload.bin with "
                "MALLOC_PERTURB_=255. Observed calls: " + repr(calls)
            )
    finally:
        shutil.copy2(backup, parser)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
