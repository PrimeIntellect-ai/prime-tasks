#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess


def test_count_txt():
    count_path = "/home/user/count.txt"
    assert os.path.isfile(count_path), f"File {count_path} does not exist."

    with open(count_path, "r") as f:
        content = f.read().strip()

    assert content == "2", f"Expected count.txt to contain '2', but got '{content}'."


def test_critical_archive_log():
    archive_path = "/home/user/critical_archive.log"
    assert os.path.isfile(archive_path), f"File {archive_path} does not exist."

    expected_content = """[2023-10-25 14:05:00] CRITICAL Disk space exhausted:
Volume /dev/sda1 has 0 bytes left.
Please free up space immediately.
[2023-10-25 14:10:00] CRITICAL Database connection lost:
Error 104: Connection reset by peer
Stack trace:
  at db_connect()
  at main()
"""

    with open(archive_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), "The content of critical_archive.log does not match the expected output."


def test_tmp_file_not_exists():
    tmp_path = "/home/user/critical_archive.log.tmp"
    assert not os.path.exists(tmp_path), f"Temporary file {tmp_path} should not exist (it should have been renamed)."


def test_archiver_cpp_contains_rename():
    cpp_path = "/home/user/archiver.cpp"
    assert os.path.isfile(cpp_path), f"Source file {cpp_path} does not exist."

    with open(cpp_path, "r") as f:
        content = f.read()

    assert re.search(r'\brename\s*\(', content), f"The word 'rename' (or 'std::rename') was not found as a function call in {cpp_path}."


def test_archiver_executable():
    exe_path = "/home/user/archiver"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_path} is not a compiled ELF executable."


def _run_case(executable, target, archive, log_data, expected_entries, extra_env=None):
    config = (
        "MAX_DAYS=17\n"
        f"ARCHIVE_FILE={archive}\n"
        "IGNORED_SETTING=anything\n"
        f"TARGET_LEVEL={target}\n"
    )
    with open("/home/user/rules.conf", "w") as f:
        f.write(config)

    with open(archive, "w") as f:
        f.write("old archive contents that must be replaced\n")
    try:
        os.unlink(archive + ".tmp")
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        [executable], input=log_data.encode(), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=env, timeout=10
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    stdout = result.stdout.decode(errors="replace")
    assert re.fullmatch(str(len(expected_entries)) + r"\n?", stdout), (
        f"Expected stdout to contain only {len(expected_entries)}, got {stdout!r}"
    )
    assert os.path.isfile(archive), "Configured archive file was not created."
    with open(archive, "rb") as f:
        actual = f.read()
    expected = "".join(expected_entries).encode()
    assert actual == expected, f"Archive content mismatch: expected {expected!r}, got {actual!r}"
    assert not os.path.exists(archive + ".tmp"), "Temporary archive was not renamed away."


def test_dynamic_behavior_and_atomic_rename():
    token = secrets.token_hex(12)
    target = "LEVEL_" + secrets.token_hex(6)
    other = "OTHER_" + secrets.token_hex(6)
    archive1 = f"/tmp/archive_{token}_one.log"
    archive2 = f"/tmp/archive_{token}_two.log"
    archive3 = f"/tmp/archive_{token}_three.log"
    rebuilt = f"/tmp/archiver_{token}"
    preload_src = f"/tmp/rename_trace_{token}.c"
    preload_so = f"/tmp/rename_trace_{token}.so"
    trace_log = f"/tmp/rename_trace_{token}.log"

    entry1 = f"[2041-01-02 03:04:05] {target} generated message {token}\ncontinuation {token}\n"
    entry2 = f"[2041-01-02 03:04:06] {other} ignored message\nignored continuation\n"
    entry3 = f"[2041-01-02 03:04:07] {target} second generated message\n  indented continuation\n"
    entry4 = f"[2041-01-02 03:04:08] {target}X exact-match decoy\n"
    log_data = entry2 + entry1 + entry4 + entry3

    with open("/home/user/rules.conf", "rb") as f:
        original_config = f.read()

    paths = [archive1, archive2, archive3, rebuilt, preload_src, preload_so, trace_log]
    try:
        _run_case("/home/user/archiver", target, archive1, log_data, [entry1, entry3])

        # A second unpredictable configuration verifies zero-match handling and
        # that an existing archive is replaced rather than stale output reused.
        absent_target = "ABSENT_" + secrets.token_hex(8)
        _run_case("/home/user/archiver", absent_target, archive2, log_data, [])

        build = subprocess.run(
            ["g++", "-std=c++17", "/home/user/archiver.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert build.returncode == 0, "archiver.cpp did not compile:\n" + build.stderr.decode(errors="replace")

        tracer = r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*rename_fn)(const char *, const char *);
int rename(const char *oldpath, const char *newpath) {
    static rename_fn real_rename = NULL;
    if (!real_rename) real_rename = (rename_fn)dlsym(RTLD_NEXT, "rename");
    const char *logpath = getenv("ARCHIVER_RENAME_TRACE");
    if (logpath) {
        int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            dprintf(fd, "%s\t%s\n", oldpath, newpath);
            close(fd);
        }
    }
    return real_rename(oldpath, newpath);
}
'''
        with open(preload_src, "w") as f:
            f.write(tracer)
        trace_build = subprocess.run(
            ["gcc", "-shared", "-fPIC", preload_src, "-o", preload_so, "-ldl"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert trace_build.returncode == 0, trace_build.stderr.decode(errors="replace")

        _run_case(
            rebuilt, target, archive3, log_data, [entry1, entry3],
            {"LD_PRELOAD": preload_so, "ARCHIVER_RENAME_TRACE": trace_log}
        )
        assert os.path.isfile(trace_log), "The rebuilt program did not call the system rename function."
        with open(trace_log, "r") as f:
            calls = [line.rstrip("\n").split("\t", 1) for line in f]
        assert [archive3 + ".tmp", archive3] in calls, (
            "The program did not rename <ARCHIVE_FILE>.tmp to <ARCHIVE_FILE>."
        )
    finally:
        with open("/home/user/rules.conf", "wb") as f:
            f.write(original_config)
        for path in paths:
            for candidate in (path, path + ".tmp"):
                try:
                    os.unlink(candidate)
                except FileNotFoundError:
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
