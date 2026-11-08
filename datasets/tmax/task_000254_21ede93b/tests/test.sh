#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import signal
import subprocess
import tempfile
import time
import uuid

import pytest

SUMMARY = "/home/user/archive/summary.json"
MASTER = "/home/user/archive/master_critical.log"
TMP_SUMMARY = "/home/user/archive/summary.tmp"
MONITOR_LOG = "/tmp/archiver_api_monitor.log"


def read_summary():
    with open(SUMMARY, "r") as f:
        return json.load(f)


def wait_for(predicate, timeout=2.0):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            last_error = exc
        time.sleep(0.04)
    if last_error:
        raise AssertionError(f"condition not met within {timeout} seconds; last error: {last_error}")
    raise AssertionError(f"condition not met within {timeout} seconds")


def kill_archivers():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm", "r") as f:
                if f.read().strip() == "archiver":
                    os.kill(int(entry), signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.15)


def monitor_records():
    try:
        with open(MONITOR_LOG, "r") as f:
            return [line.rstrip("\n").split("\t") for line in f]
    except FileNotFoundError:
        return []


def successful_renames(records):
    return [r for r in records if len(r) == 4 and r[0] == "R" and r[1] == TMP_SUMMARY and r[2] == SUMMARY and r[3] == "0"]


def write_monitor_library():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/inotify.h>
#include <unistd.h>

static void record_line(const char *line) {
    const char *path = getenv("ARCHIVER_MONITOR_LOG");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        size_t n = 0;
        while (line[n]) n++;
        (void)write(fd, line, n);
        close(fd);
    }
}

FILE *popen(const char *command, const char *type) {
    static FILE *(*real_popen)(const char *, const char *);
    if (!real_popen) real_popen = dlsym(RTLD_NEXT, "popen");
    char buf[4096];
    snprintf(buf, sizeof(buf), "P\t%s\n", command ? command : "(null)");
    record_line(buf);
    return real_popen(command, type);
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    int rc = real_rename(oldpath, newpath);
    char buf[4096];
    snprintf(buf, sizeof(buf), "R\t%s\t%s\t%d\n", oldpath, newpath, rc);
    record_line(buf);
    return rc;
}

int inotify_init(void) {
    static int (*real_fn)(void);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "inotify_init");
    int rc = real_fn();
    record_line("I\tinotify_init\n");
    return rc;
}

int inotify_init1(int flags) {
    static int (*real_fn)(int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "inotify_init1");
    int rc = real_fn(flags);
    record_line("I\tinotify_init1\n");
    return rc;
}

int inotify_add_watch(int fd, const char *pathname, uint32_t mask) {
    static int (*real_fn)(int, const char *, uint32_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "inotify_add_watch");
    int rc = real_fn(fd, pathname, mask);
    char buf[4096];
    snprintf(buf, sizeof(buf), "W\t%s\t%u\n", pathname ? pathname : "(null)", mask);
    record_line(buf);
    return rc;
}
'''
    src = "/tmp/archiver_api_monitor.c"
    so = "/tmp/archiver_api_monitor.so"
    with open(src, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", so, src, "-ldl"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"could not build verifier monitor: {result.stderr}"
    return so


def test_archiver_daemon():
    # Preserve the original final-state assertions.
    filter_script = "/home/user/filter.sh"
    assert os.path.isfile(filter_script), f"{filter_script} does not exist."
    assert os.access(filter_script, os.X_OK), f"{filter_script} is not executable."

    archiver_bin = "/home/user/archiver"
    assert os.path.isfile(archiver_bin), f"{archiver_bin} does not exist. Did you compile it?"
    assert os.access(archiver_bin, os.X_OK), f"{archiver_bin} is not executable."

    try:
        ps_output = subprocess.check_output(["ps", "-A", "-o", "comm"]).decode()
        assert "archiver" in ps_output, "The archiver daemon is not running in the background."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check running processes.")

    assert os.path.isfile(SUMMARY), f"{SUMMARY} does not exist."
    try:
        summary = read_summary()
    except json.JSONDecodeError:
        pytest.fail(f"{SUMMARY} does not contain valid JSON.")
    assert summary.get("total_critical") == 2, f"Expected total_critical to be 2, got {summary.get('total_critical')}"

    assert os.path.isfile(MASTER), f"{MASTER} does not exist."
    with open(MASTER, "r") as f:
        initial_lines = f.read().splitlines()
    expected_initial_lines = {
        "[CRITICAL] Backup failed on /dev/sda1",
        "[CRITICAL] Connection timeout to backup server",
    }
    assert set(initial_lines) == expected_initial_lines, "master_critical.log does not contain the expected initial critical lines."

    incoming_file = "/home/user/incoming/test.log"
    with open(incoming_file, "w") as f:
        f.write("INFO: OK\n[CRITICAL] Incoming failure 1\n[CRITICAL] Incoming failure 2\n")
    time.sleep(2)

    try:
        summary = read_summary()
    except json.JSONDecodeError:
        pytest.fail(f"{SUMMARY} does not contain valid JSON after update.")
    assert summary.get("total_critical") == 4, f"Expected total_critical to be 4 after incoming file, got {summary.get('total_critical')}"

    with open(MASTER, "r") as f:
        final_lines = f.read().splitlines()
    expected_new_lines = {
        "[CRITICAL] Incoming failure 1",
        "[CRITICAL] Incoming failure 2",
    }
    assert len(final_lines) == 4, f"Expected exactly 4 lines in {MASTER}, got {len(final_lines)}."
    assert expected_initial_lines.union(expected_new_lines) == set(final_lines), "master_critical.log does not contain all expected lines after incoming file processing."

    # Verify the requested source exists and remains compilable with the specified command.
    source_path = "/home/user/archiver.c"
    assert os.path.isfile(source_path), f"{source_path} does not exist."
    compile_result = subprocess.run(
        ["gcc", "-o", "/tmp/verifier_archiver_build", source_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"archiver.c does not compile with the required gcc command: {compile_result.stderr}"

    # Exercise filter.sh on unpredictable data rather than trusting the fixture strings.
    token = uuid.uuid4().hex
    filter_input = f"/tmp/filter-{token}.txt"
    wanted_filter = [f"prefix [CRITICAL] {token}-a", f"[CRITICAL] {token}-b suffix"]
    with open(filter_input, "w") as f:
        f.write(f"[critical] {token}-wrong-case\n")
        f.write(wanted_filter[0] + "\n")
        f.write(f"CRITICAL {token}-missing-brackets\n")
        f.write(wanted_filter[1] + "\n")
    filtered = subprocess.run([filter_script, filter_input], check=True, stdout=subprocess.PIPE, text=True).stdout.splitlines()
    assert filtered == wanted_filter, "filter.sh must output only lines containing the exact string [CRITICAL]."

    # Restart under API instrumentation with randomized recursive and incoming files.
    kill_archivers()
    for root, dirs, files in os.walk("/home/user/legacy_logs", topdown=False):
        for name in files:
            os.unlink(os.path.join(root, name))
        for name in dirs:
            os.rmdir(os.path.join(root, name))
    for name in os.listdir("/home/user/incoming"):
        path = os.path.join("/home/user/incoming", name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    os.makedirs("/home/user/legacy_logs", exist_ok=True)
    os.makedirs("/home/user/incoming", exist_ok=True)
    os.makedirs("/home/user/archive", exist_ok=True)
    for path in (SUMMARY, MASTER, TMP_SUMMARY, MONITOR_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    deep = f"/home/user/legacy_logs/{token[:8]}/nested/deeper"
    os.makedirs(deep, exist_ok=True)
    legacy_files = {
        f"/home/user/legacy_logs/root-{token}.log": [f"[CRITICAL] legacy-root-{token}"],
        f"/home/user/legacy_logs/{token[:8]}/nested/mid-{token}.log": [
            f"before [CRITICAL] legacy-mid-a-{token}",
            f"[CRITICAL] legacy-mid-b-{token}",
        ],
        f"{deep}/empty-critical-{token}.log": [],
    }
    for path, critical in legacy_files.items():
        with open(path, "w") as f:
            f.write(f"INFO noncritical {token}\n")
            for line in critical:
                f.write(line + "\n")
            f.write(f"[critical] wrong-case {token}\n")
    with open(f"{deep}/ignored-{token}.txt", "w") as f:
        f.write(f"[CRITICAL] must-not-archive-{token}\n")

    monitor_so = write_monitor_library()
    env = os.environ.copy()
    env["LD_PRELOAD"] = monitor_so
    env["ARCHIVER_MONITOR_LOG"] = MONITOR_LOG
    proc = subprocess.Popen([archiver_bin], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        expected_legacy = [line for lines in legacy_files.values() for line in lines]

        def legacy_ready():
            if not os.path.isfile(SUMMARY) or not os.path.isfile(MASTER):
                return False
            if read_summary().get("total_critical") != len(expected_legacy):
                return False
            with open(MASTER, "r") as f:
                return collections.Counter(f.read().splitlines()) == collections.Counter(expected_legacy)

        wait_for(legacy_ready)

        def watcher_ready():
            for r in monitor_records():
                if len(r) == 3 and r[0] == "W" and os.path.normpath(r[1]) == "/home/user/incoming" and (int(r[2]) & 0x00000008):
                    return True
            return False

        wait_for(watcher_ready)
        initial_records = monitor_records()
        initial_renames = successful_renames(initial_records)
        assert len(initial_renames) >= len(legacy_files), "summary.json was not atomically replaced via summary.tmp and rename() after every legacy .log file."

        popen_commands = [r[1] for r in initial_records if len(r) >= 2 and r[0] == "P"]
        for path in legacy_files:
            assert any("/home/user/filter.sh" in cmd and path in cmd for cmd in popen_commands), f"legacy file {path} was not passed to filter.sh via popen()."

        ignored_incoming = f"/home/user/incoming/ignored-{token}.txt"
        with open(ignored_incoming, "w") as f:
            f.write(f"[CRITICAL] ignored-incoming-{token}\n")

        incoming_files = {
            f"/home/user/incoming/first-{token}.log": [
                f"[CRITICAL] incoming-a-{token}",
                f"text [CRITICAL] incoming-b-{token}",
            ],
            f"/home/user/incoming/zero-{token}.log": [],
        }
        for path, critical in incoming_files.items():
            with open(path, "w") as f:
                f.write(f"INFO incoming {token}\n")
                for line in critical:
                    f.write(line + "\n")
                f.write(f"[CRITICAL ] near-miss {token}\n")

        expected_all = expected_legacy + [line for lines in incoming_files.values() for line in lines]

        def incoming_ready():
            if read_summary().get("total_critical") != len(expected_all):
                return False
            with open(MASTER, "r") as f:
                return collections.Counter(f.read().splitlines()) == collections.Counter(expected_all)

        wait_for(incoming_ready)
        records = monitor_records()
        renames = successful_renames(records)
        assert len(renames) >= len(initial_renames) + len(incoming_files), "summary.json was not atomically replaced via summary.tmp and rename() after every incoming .log file."
        assert not os.path.exists(TMP_SUMMARY), "summary.tmp was left behind after the atomic update."

        all_popen_commands = [r[1] for r in records if len(r) >= 2 and r[0] == "P"]
        for path in incoming_files:
            assert any("/home/user/filter.sh" in cmd and path in cmd for cmd in all_popen_commands), f"incoming file {path} was not passed to filter.sh via popen()."

        assert any(r[0] == "I" for r in records), "archiver did not initialize inotify."
        assert watcher_ready(), "archiver did not install an IN_CLOSE_WRITE inotify watch on /home/user/incoming/."
        with open(MASTER, "r") as f:
            archived_text = f.read()
        assert f"must-not-archive-{token}" not in archived_text
        assert f"ignored-incoming-{token}" not in archived_text
    finally:
        try:
            proc.kill()
            proc.wait(timeout=1)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            pass
        kill_archivers()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
