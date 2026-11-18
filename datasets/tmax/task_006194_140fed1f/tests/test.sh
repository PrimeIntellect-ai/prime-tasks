#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_dataport.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

WORKDIR = "/home/user/dataport"
MAKEFILE_PATH = os.path.join(WORKDIR, "Makefile")
SOURCE_PATH = os.path.join(WORKDIR, "processor.cpp")
PROCESSOR_DYN_PATH = os.path.join(WORKDIR, "processor_dyn")
PROCESSOR_STATIC_PATH = os.path.join(WORKDIR, "processor_static")
LOG_PATH = os.path.join(WORKDIR, "minimal_run.log")
DB_PATH = os.path.join(WORKDIR, "data.db")


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", WORKDIR)
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 120)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def file_description(path):
    return run(["file", path], cwd="/").stdout


def create_fresh_database(values):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, value TEXT)")
    conn.executemany(
        "INSERT INTO records(id, value) VALUES (?, ?)",
        [(i + 1, value) for i, value in enumerate(values)],
    )
    conn.commit()
    conn.close()


def verify_database(values):
    conn = sqlite3.connect(DB_PATH)
    columns = [row[1] for row in conn.execute("PRAGMA table_info(records)")]
    assert "processed_value" in columns, "Program did not perform the schema migration."
    rows = conn.execute(
        "SELECT id, value, processed_value FROM records ORDER BY id"
    ).fetchall()
    conn.close()
    expected = [
        (i + 1, value, value + "_processed")
        for i, value in enumerate(values)
    ]
    assert rows == expected, f"Incorrect processed rows: {rows[:5]}"


def generated_values(tag):
    count = 23 + (os.urandom(1)[0] % 25)
    nonce = os.urandom(8).hex()
    return [f"{tag}_{nonce}_{i}_value" for i in range(1, count + 1)]


def run_nonminimal(executable, values, env=None):
    create_fresh_database(values)
    result = run([executable], env=env)
    assert result.stdout.strip() == f"Processed {len(values)} records.", (
        f"Non-minimal output was {result.stdout!r}"
    )
    verify_database(values)


def run_minimal(executable, values):
    create_fresh_database(values)
    result = run([executable])
    assert result.stdout.strip() == "", "Minimal build wrote its completion message to stdout."
    assert os.path.exists(LOG_PATH), "Minimal build did not create minimal_run.log."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == f"Processed {len(values)} records.", (
        f"Incorrect minimal log contents: {content!r}"
    )
    verify_database(values)


# Preserve and retain all checks made by the original verifier.
assert os.path.exists(MAKEFILE_PATH), f"{MAKEFILE_PATH} does not exist."
with open(MAKEFILE_PATH, "r") as f:
    makefile_content = f.read()
assert (
    "default:" in makefile_content
    or "default :" in makefile_content
    or ".PHONY: default" in makefile_content
    or "all:" in makefile_content
), "Makefile missing 'default' target."
assert "minimal:" in makefile_content or "minimal :" in makefile_content, \
    "Makefile missing 'minimal' target."

assert os.path.exists(PROCESSOR_STATIC_PATH), f"{PROCESSOR_STATIC_PATH} does not exist."
assert "statically linked" in file_description(PROCESSOR_STATIC_PATH), \
    f"{PROCESSOR_STATIC_PATH} is not statically linked."

assert os.path.exists(LOG_PATH), f"{LOG_PATH} does not exist."
with open(LOG_PATH, "r") as f:
    original_log = f.read().strip()
assert "Processed 1000 records." in original_log, \
    f"Log file does not contain expected output. Found: {original_log}"

assert os.path.exists(DB_PATH), f"{DB_PATH} does not exist."
conn = sqlite3.connect(DB_PATH)
columns = [row[1] for row in conn.execute("PRAGMA table_info(records)")]
assert "processed_value" in columns, \
    "Column 'processed_value' was not added to 'records' table."
count = conn.execute(
    "SELECT count(*) FROM records WHERE processed_value = value || '_processed'"
).fetchone()[0]
conn.close()
assert count == 1000, f"Expected 1000 updated records, but found {count}."

assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
with open(SOURCE_PATH, "r") as f:
    source = f.read()
for primitive in ("thread", "mutex", "condition_variable"):
    assert re.search(r"std\s*::\s*" + primitive + r"\b", source), \
        f"processor.cpp does not use std::{primitive}."
assert re.search(r"\bMINIMAL_CONTAINER\b", source), \
    "processor.cpp does not check MINIMAL_CONTAINER."

saved_db = open(DB_PATH, "rb").read()
saved_log = open(LOG_PATH, "rb").read()
tmpdir = tempfile.mkdtemp(prefix="dataport_verify_")
try:
    # Force both submitted Makefile targets to create fresh artifacts.
    for path in (PROCESSOR_DYN_PATH, PROCESSOR_STATIC_PATH):
        if os.path.lexists(path):
            os.remove(path)
    run(["make", "-B", "default"])
    run(["make", "-B", "minimal"])

    assert os.path.isfile(PROCESSOR_DYN_PATH) and os.access(PROCESSOR_DYN_PATH, os.X_OK), \
        "The default target did not produce executable processor_dyn."
    assert os.path.isfile(PROCESSOR_STATIC_PATH) and os.access(PROCESSOR_STATIC_PATH, os.X_OK), \
        "The minimal target did not produce executable processor_static."
    dyn_desc = file_description(PROCESSOR_DYN_PATH)
    static_desc = file_description(PROCESSOR_STATIC_PATH)
    assert "ELF" in dyn_desc and "dynamically linked" in dyn_desc, \
        f"processor_dyn is not a dynamically linked ELF: {dyn_desc}"
    assert "ELF" in static_desc and "statically linked" in static_desc, \
        f"processor_static is not a statically linked ELF: {static_desc}"

    # Exercise the Makefile-produced programs on fresh, unpredictable contents.
    run_nonminimal(PROCESSOR_DYN_PATH, generated_values("make_dynamic"))
    run_minimal(PROCESSOR_STATIC_PATH, generated_values("make_static"))

    # Compile the submitted source directly, so Makefile recipes cannot substitute
    # unrelated executables.
    direct_dyn = os.path.join(tmpdir, "direct_dynamic")
    direct_static = os.path.join(tmpdir, "direct_static")
    run([
        "g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", direct_dyn,
        "-lsqlite3", "-pthread"
    ], cwd=WORKDIR)
    run([
        "g++", "-std=c++17", "-O2", "-DMINIMAL_CONTAINER", "-static",
        SOURCE_PATH, "-o", direct_static, "-lsqlite3", "-pthread", "-ldl", "-lm"
    ], cwd=WORKDIR)
    assert "dynamically linked" in file_description(direct_dyn)
    assert "statically linked" in file_description(direct_static)

    # Instrument pthread creation and condition-variable notification. A correct
    # run has one producer thread and four worker threads and uses the channel's
    # condition variable.
    hook_source = os.path.join(tmpdir, "pthread_hook.c")
    hook_library = os.path.join(tmpdir, "pthread_hook.so")
    events_path = os.path.join(tmpdir, "pthread_events")
    with open(hook_source, "w") as f:
        f.write(r'''
#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static void event(char c) {
    const char *p = getenv("DATAPORT_THREAD_EVENTS");
    if (!p) return;
    int fd = open(p, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { write(fd, &c, 1); close(fd); }
}

int pthread_create(pthread_t *t, const pthread_attr_t *a,
                   void *(*fn)(void *), void *arg) {
    static int (*real_fn)(pthread_t *, const pthread_attr_t *,
                          void *(*)(void *), void *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "pthread_create");
    int r = real_fn(t, a, fn, arg);
    if (r == 0) event('T');
    return r;
}

int pthread_cond_signal(pthread_cond_t *c) {
    static int (*real_fn)(pthread_cond_t *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "pthread_cond_signal");
    event('C');
    return real_fn(c);
}

int pthread_cond_broadcast(pthread_cond_t *c) {
    static int (*real_fn)(pthread_cond_t *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "pthread_cond_broadcast");
    event('C');
    return real_fn(c);
}
''')
    run(["gcc", "-shared", "-fPIC", hook_source, "-o", hook_library, "-ldl", "-pthread"], cwd="/")
    env = os.environ.copy()
    env["LD_PRELOAD"] = hook_library
    env["DATAPORT_THREAD_EVENTS"] = events_path
    run_nonminimal(direct_dyn, generated_values("direct_dynamic"), env=env)
    with open(events_path, "r") as f:
        events = f.read()
    assert events.count("T") == 5, \
        f"Expected one producer and four worker threads, observed {events.count('T')} threads."
    assert events.count("C") > 0, \
        "No condition-variable notification was observed during processing."

    run_minimal(direct_static, generated_values("direct_static"))
finally:
    with open(DB_PATH, "wb") as f:
        f.write(saved_db)
    with open(LOG_PATH, "wb") as f:
        f.write(saved_log)
    shutil.rmtree(tmpdir, ignore_errors=True)
PY_EOF

if python3 /tmp/test_dataport.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
