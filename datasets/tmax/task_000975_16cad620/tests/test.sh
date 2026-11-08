#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from collections import Counter

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/loc_parser.c"
PARSER = f"{HOME}/loc_parser"
SCRIPT = f"{HOME}/process_locales.sh"
CSV_PATH = f"{HOME}/valid_translations.csv"
LOCALES = f"{HOME}/locales"

EXPECTED_SCRIPT_LINES = [
    r"alpha,Plain translation",
    r"beta,Copyright \u00A9",
    r"delta,Two \u1A2B sequences \u3c4D",
    r"punct,Wait, please!",
    r"zeta,Done\u0021",
    r"eta,No escapes here",
]


def run_checked(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def build_and_execute_submission():
    # Preserve the original final-state existence and permission requirements.
    assert os.path.isfile(SOURCE), "C source file /home/user/loc_parser.c is missing."
    assert os.path.isfile(PARSER), "Compiled executable /home/user/loc_parser is missing."
    assert os.access(PARSER, os.X_OK), "/home/user/loc_parser is not executable."
    assert os.path.isfile(SCRIPT), "Shell script /home/user/process_locales.sh is missing."
    assert os.access(SCRIPT, os.X_OK), "/home/user/process_locales.sh is not executable."

    # Independently compile the submitted C source, rather than trusting the
    # executable left by the agent.
    verifier_parser = "/tmp/verifier_loc_parser"
    compile_result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", "-o", verifier_parser, SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "loc_parser.c did not compile successfully:\n" + compile_result.stderr
    )
    assert "warning:" not in compile_result.stderr.lower(), (
        "loc_parser.c did not compile cleanly:\n" + compile_result.stderr
    )

    # Confirm the compiled artifact really references the POSIX regex API.
    symbols = run_checked(["nm", "-D", verifier_parser]).stdout
    assert re.search(r"\bregcomp(?:@|$)", symbols), "The parser does not use regcomp from <regex.h>."
    assert re.search(r"\bregexec(?:@|$)", symbols), "The parser does not use regexec from <regex.h>."

    # Exercise the independently compiled parser on hidden valid, invalid, and
    # malformed records. Expected output is fixed by the verifier, not by the
    # writable locale directory.
    direct_input = (
        r'{"msgid": "plain", "msgstr": "Text with spaces, punctuation!"}' "\n"
        r'{"msgid": "valid1", "msgstr": "Mark \u00A9 end"}' "\n"
        r'{"msgid": "valid2", "msgstr": "Two \u1a2B and \uF8A0"}' "\n"
        r'{"msgid": "badhex", "msgstr": "Bad \u12Z3"}' "\n"
        r'{"msgid": "short", "msgstr": "Bad \u12"}' "\n"
        r'{"msgid": "mixed", "msgstr": "Good \u1234 bad \uABCZ"}' "\n"
        'not a JSON record\n'
    )
    direct = subprocess.run(
        [verifier_parser], input=direct_input, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert direct.returncode == 0, f"Parser failed on stdin: {direct.stderr}"
    assert direct.stdout.splitlines() == [
        "plain,Text with spaces, punctuation!",
        r"valid1,Mark \u00A9 end",
        r"valid2,Two \u1a2B and \uF8A0",
    ], f"Unexpected parser output: {direct.stdout!r}"

    # Replace the agent-writable fixtures with verifier-controlled inputs.
    os.makedirs(LOCALES, exist_ok=True)
    for name in os.listdir(LOCALES):
        path = os.path.join(LOCALES, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    fixtures = {
        "hidden1.jsonl": (
            r'{"msgid": "alpha", "msgstr": "Plain translation"}' "\n"
            r'{"msgid": "bad1", "msgstr": "Corrupt \u0G00"}' "\n"
        ),
        "hidden2.jsonl": (
            r'{"msgid": "beta", "msgstr": "Copyright \u00A9"}' "\n"
            r'{"msgid": "bad2", "msgstr": "Short \u123"}' "\n"
        ),
        "hidden3.jsonl": (
            r'{"msgid": "delta", "msgstr": "Two \u1A2B sequences \u3c4D"}' "\n"
        ),
        "hidden4.jsonl": (
            r'{"msgid": "punct", "msgstr": "Wait, please!"}' "\n"
            r'{"msgid": "bad3", "msgstr": "One \u1234 then \uZZZZ"}' "\n"
        ),
        "hidden5.jsonl": r'{"msgid": "zeta", "msgstr": "Done\u0021"}' "\n",
        "hidden6.jsonl": r'{"msgid": "eta", "msgstr": "No escapes here"}' "\n",
    }
    for name, contents in fixtures.items():
        with open(os.path.join(LOCALES, name), "w", encoding="utf-8") as f:
            f.write(contents)

    # Build an LD_PRELOAD probe. Each loc_parser process briefly records its
    # presence, allowing the verifier to distinguish concurrent processing from
    # a sequential loop without modifying the submitted source.
    probe_c = r'''
#define _GNU_SOURCE
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static void update_state(int delta) {
    int fd = open("/tmp/loc_parallel_state", O_RDWR | O_CREAT, 0666);
    if (fd < 0) return;
    flock(fd, LOCK_EX);
    char buf[128] = {0};
    int active = 0, maximum = 0;
    lseek(fd, 0, SEEK_SET);
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) sscanf(buf, "%d %d", &active, &maximum);
    active += delta;
    if (active > maximum) maximum = active;
    lseek(fd, 0, SEEK_SET);
    ftruncate(fd, 0);
    dprintf(fd, "%d %d\n", active, maximum);
    flock(fd, LOCK_UN);
    close(fd);
}

__attribute__((constructor)) static void observe_parser(void) {
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n < 0) return;
    exe[n] = '\0';
    char *base = strrchr(exe, '/');
    base = base ? base + 1 : exe;
    if (strcmp(base, "loc_parser") != 0) return;
    update_state(1);
    usleep(400000);
    update_state(-1);
}
'''
    with open("/tmp/parallel_probe.c", "w", encoding="utf-8") as f:
        f.write(probe_c)
    run_checked(["gcc", "-shared", "-fPIC", "-o", "/tmp/parallel_probe.so",
                 "/tmp/parallel_probe.c"])
    with open("/tmp/loc_parallel_state", "w", encoding="ascii") as f:
        f.write("0 0\n")

    # Force the script to produce the executable itself, then execute it.
    os.unlink(PARSER)
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/parallel_probe.so"
    script_result = subprocess.run(
        [SCRIPT], cwd=HOME, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert script_result.returncode == 0, (
        f"process_locales.sh failed.\nstdout:\n{script_result.stdout}"
        f"\nstderr:\n{script_result.stderr}"
    )


def test_files_exist():
    assert os.path.exists(SOURCE), "C source file /home/user/loc_parser.c is missing."
    assert os.path.exists(PARSER), "Compiled executable /home/user/loc_parser is missing."
    assert os.access(PARSER, os.X_OK), "/home/user/loc_parser is not executable."
    assert os.path.exists(SCRIPT), "Shell script /home/user/process_locales.sh is missing."
    assert os.access(SCRIPT, os.X_OK), "/home/user/process_locales.sh is not executable."


def test_script_compiles_and_processes_in_parallel():
    with open(SCRIPT, "r", encoding="utf-8") as f:
        script = f.read()
    active = "\n".join(line for line in script.splitlines()
                       if not line.lstrip().startswith("#"))
    source_pos = active.find("loc_parser.c")
    parallel_match = re.search(r"(?:\bparallel\b|\bxargs\b[^\n]*\s-P\s*\d+)", active)
    assert source_pos >= 0, "The script does not compile loc_parser.c."
    assert parallel_match, "The script does not invoke GNU parallel or xargs -P."
    assert source_pos < parallel_match.start(), "The script must compile before parallel processing."

    with open("/tmp/loc_parallel_state", "r", encoding="ascii") as f:
        active_count, maximum = map(int, f.read().split())
    assert active_count == 0, "A parser process did not finish cleanly."
    assert maximum >= 2, "Locale files were not actually processed concurrently."


def test_output_csv_exists():
    assert os.path.exists(CSV_PATH), "Output file /home/user/valid_translations.csv is missing."


def test_output_csv_content():
    assert os.path.exists(CSV_PATH), "Cannot check content, CSV missing."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, "CSV file is empty."
    assert lines[0] == "msgid,msgstr", (
        f"Incorrect header in CSV. Expected 'msgid,msgstr', got '{lines[0]}'."
    )
    actual = lines[1:]
    assert Counter(actual) == Counter(EXPECTED_SCRIPT_LINES), (
        f"CSV records differ. Expected {EXPECTED_SCRIPT_LINES!r}, got {actual!r}"
    )
    assert len(actual) == len(EXPECTED_SCRIPT_LINES), (
        f"Expected exactly {len(EXPECTED_SCRIPT_LINES)} data lines, got {len(actual)}."
    )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
