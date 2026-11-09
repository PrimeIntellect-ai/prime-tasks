#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile

SCRIPT = "/home/user/run_audit.sh"
SOURCE = "/home/user/net_parser.c"
RULES = "/home/user/rules.txt"
BINARY = "/home/user/net_parser"
LOG = "/home/user/audit_report.log"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 10)
    return subprocess.run(cmd, **kwargs)


def test_run_audit_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_net_parser_compiles_cleanly():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    result = run(["gcc", "-Wall", "-Werror", "-o", "/dev/null", SOURCE])
    assert result.returncode == 0, (
        "net_parser.c failed to compile cleanly (without warnings):\n"
        + result.stderr
    )


def test_run_audit_execution_and_output():
    assert os.path.isfile(RULES), f"{RULES} does not exist."
    if os.path.exists(LOG):
        os.remove(LOG)
    if os.path.exists(BINARY):
        os.remove(BINARY)

    result = run([SCRIPT])
    assert result.returncode == 0, (
        f"Executing {SCRIPT} failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(LOG), f"{LOG} was not created by the script."
    assert os.path.isfile(BINARY), f"{BINARY} was not created by the script."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    with open(LOG) as f:
        log_content = f.read().strip().splitlines()

    expected_log = [
        "Audit - Action: FORWARD, Mapping: 8080->80",
        "Audit - Action: FORWARD, Mapping: 9000->9000",
        "Audit - Action: DROP, Mapping: 22",
        "Audit - Action: FORWARD, Mapping: 443->8443",
    ]
    assert log_content == expected_log, (
        f"Content of {LOG} does not match expected output.\n"
        f"Expected:\n{expected_log}\nGot:\n{log_content}"
    )


def test_script_environment_variables():
    with open(SCRIPT) as f:
        content = f.read()
    assert "TZ=UTC" in content or "export TZ=UTC" in content, "Script does not set TZ to UTC."
    assert "LC_ALL=C" in content or "export LC_ALL=C" in content, "Script does not set LC_ALL to C."


def test_parser_handles_generated_malformed_input_line_by_line():
    values = random.sample(range(1000, 60000), 6)
    p1, p2, p3, p4, p5, p6 = values
    fixture = (
        f"FORWARD {p1} {p2}\n"
        "BROKEN\n"
        f"FORWARD {p3} {p4}\n"
        "FORWARD not_an_integer 9\n"
        f"DROP {p5} -1\n"
        "FORWARD 7\n"
        f"FORWARD {p6} 80\n"
        "\n"
    )
    expected = [
        f"[VALID] FORWARD {p1} {p2}",
        f"[VALID] FORWARD {p3} {p4}",
        f"[VALID] DROP {p5} -1",
        f"[VALID] FORWARD {p6} 80",
    ]

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "net_parser")
        fixture_path = os.path.join(td, "rules.txt")
        with open(fixture_path, "w") as f:
            f.write(fixture)
        compiled = run(["gcc", "-Wall", "-Werror", "-o", executable, SOURCE])
        assert compiled.returncode == 0, compiled.stderr
        result = run([executable, fixture_path], timeout=3)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip().splitlines() == expected


def test_script_really_compiles_executes_formats_and_scopes_environment():
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    with open(RULES, "rb") as f:
        original_rules = f.read()

    nonce = "%016x" % random.getrandbits(64)
    first = random.randint(12000, 30000)
    second = random.randint(30001, 60000)
    drop_port = random.randint(1000, 11000)
    marker = f"/tmp/audit_probe_{nonce}"

    probe_source = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *tz = getenv("TZ");
    const char *lc = getenv("LC_ALL");
    FILE *marker;
    if (argc != 2 || strcmp(argv[1], "/home/user/rules.txt") != 0) return 41;
    marker = fopen("%s", "w");
    if (marker == NULL) return 42;
    fprintf(marker, "%s\n%s\n%s\n", "%s", tz ? tz : "(null)", lc ? lc : "(null)");
    fclose(marker);
    printf("[VALID] FORWARD %d %d\n");
    puts("this output is not valid and must not be reported");
    printf("[VALID] DROP %d -1\n");
    return 0;
}
''' % (marker, nonce, "%s", "%s", first, second, drop_port)

    try:
        with open(SOURCE, "w") as f:
            f.write(probe_source)
        with open(RULES, "w") as f:
            f.write("probe input; the temporary executable validates its path\n")
        for path in (BINARY, LOG, marker):
            if os.path.exists(path):
                os.remove(path)

        env = os.environ.copy()
        env["TZ"] = "Pacific/Honolulu"
        env["LC_ALL"] = "C.UTF-8"
        result = run(["bash", "-x", SCRIPT], env=env)
        assert result.returncode == 0, result.stderr

        assert os.path.isfile(marker), (
            "The executable compiled from net_parser.c was not run by run_audit.sh."
        )
        with open(marker) as f:
            marker_lines = f.read().splitlines()
        assert marker_lines == [nonce, "UTC", "C"], (
            "The parser was not executed with TZ=UTC and LC_ALL=C: "
            + repr(marker_lines)
        )

        assert os.path.isfile(BINARY), "run_audit.sh did not create /home/user/net_parser."
        with open(BINARY, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        assert os.path.isfile(LOG), "run_audit.sh did not create audit_report.log."
        with open(LOG) as f:
            actual = f.read().strip().splitlines()
        expected = [
            f"Audit - Action: FORWARD, Mapping: {first}->{second}",
            f"Audit - Action: DROP, Mapping: {drop_port}",
        ]
        assert actual == expected, f"Expected dynamically generated report {expected}, got {actual}"

        with open(SCRIPT) as f:
            script_content = f.read()
        active_lines = [line for line in script_content.splitlines() if not line.lstrip().startswith("#")]
        assert any("|" in line and re.search(r"\b(awk|sed|grep)\b", line) for line in active_lines), (
            "run_audit.sh does not contain a text-processing pipeline using awk, sed, or grep."
        )
        assert re.search(r"(?m)^\+ .*?(?:^|/)(?:awk|sed|grep)(?:\s|$)", result.stderr), (
            "No awk, sed, or grep command was actually executed by run_audit.sh."
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        with open(RULES, "wb") as f:
            f.write(original_rules)
        if os.path.exists(marker):
            os.remove(marker)
        restored = run(["gcc", "-Wall", "-Werror", "-o", BINARY, SOURCE])
        assert restored.returncode == 0, restored.stderr
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
