#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import collections
import glob
import os
import random
import shutil
import string
import subprocess
import tempfile

HOME = "/home/user"
PIPELINE = os.path.join(HOME, "pipeline.sh")
SOURCE = os.path.join(HOME, "validate.c")
STREAM = os.path.join(HOME, "config_stream.csv")
VALIDATOR = os.path.join(HOME, "validate")


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=HOME, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, **kwargs)


def clean_intermediates():
    for pattern in ("split_*.csv", "valid_*.csv", "invalid_*.csv"):
        for path in glob.glob(os.path.join(HOME, pattern)):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def classify(line):
    fields = line.split(",")
    if len(fields) != 6:
        return False
    timestamp, user, region, config_key, action, value = fields
    try:
        timestamp_ok = str(int(timestamp)) == timestamp and int(timestamp) > 1600000000
    except ValueError:
        timestamp_ok = False
    return timestamp_ok and bool(user) and len(region) == 2 and action in {"ADD", "MOD", "DEL"}


def read_lines(path):
    with open(path, "r", newline="") as f:
        return [line.rstrip("\r\n") for line in f]


INSTRUMENTED_SOURCE = r'''
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int active_count(void) {
    DIR *d = opendir("/tmp");
    struct dirent *e;
    int n = 0;
    if (!d) return 0;
    while ((e = readdir(d)) != NULL)
        if (strncmp(e->d_name, "pipeline_active_", 16) == 0) n++;
    closedir(d);
    return n;
}

static int valid_line(char *line) {
    char *copy = strdup(line);
    char *p = copy;
    char *f[7] = {0};
    char *end;
    long long ts;
    int i;
    if (!copy) return 0;
    copy[strcspn(copy, "\r\n")] = '\0';
    for (i = 0; i < 7 && p != NULL; i++) f[i] = strsep(&p, ",");
    if (i != 6 || p != NULL) { free(copy); return 0; }
    errno = 0;
    ts = strtoll(f[0], &end, 10);
    if (errno || *f[0] == '\0' || *end != '\0' || ts <= 1600000000LL ||
        *f[1] == '\0' || strlen(f[2]) != 2 ||
        (strcmp(f[4], "ADD") && strcmp(f[4], "MOD") && strcmp(f[4], "DEL"))) {
        free(copy);
        return 0;
    }
    free(copy);
    return 1;
}

int main(int argc, char **argv) {
    char marker[128], seen_name[128];
    FILE *in, *out_valid, *out_invalid, *seen;
    char *line = NULL;
    size_t cap = 0;
    int i, concurrent = 0;
    if (argc != 4) return 2;

    snprintf(marker, sizeof(marker), "/tmp/pipeline_active_%ld", (long)getpid());
    snprintf(seen_name, sizeof(seen_name), "/tmp/pipeline_seen_%ld", (long)getpid());
    close(open(marker, O_WRONLY | O_CREAT | O_TRUNC, 0600));
    seen = fopen(seen_name, "w");
    if (!seen) return 3;
    fprintf(seen, "%s\n", argv[1]);
    fflush(seen);

    for (i = 0; i < 300; i++) {
        if (active_count() >= 4) { concurrent = 1; break; }
        usleep(10000);
    }
    if (!concurrent) close(open("/tmp/pipeline_concurrency_failed", O_WRONLY | O_CREAT | O_TRUNC, 0600));

    in = fopen(argv[1], "r");
    out_valid = fopen(argv[2], "w");
    out_invalid = fopen(argv[3], "w");
    if (!in || !out_valid || !out_invalid) return 4;
    while (getline(&line, &cap, in) != -1) {
        fputs(line, seen);
        fputs(line, valid_line(line) ? out_valid : out_invalid);
    }
    usleep(200000);
    free(line);
    fclose(in);
    fclose(out_valid);
    fclose(out_invalid);
    fclose(seen);
    unlink(marker);
    return 0;
}
'''

original_source = open(SOURCE, "rb").read()
original_stream = open(STREAM, "rb").read()
failure = None

try:
    # Execute the submitted pipeline once before testing the resulting validator.
    clean_intermediates()
    result = run([PIPELINE])
    assert result.returncode == 0, f"pipeline.sh failed:\n{result.stderr}"
    assert os.path.isfile(VALIDATOR) and os.access(VALIDATOR, os.X_OK)

    # Exercise the submitted validator on data generated only at verification time.
    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(12))
    rows = [
        f"{rng.randrange(1600000001, 2100000000)},{token}a,ZX,key,ADD,1",
        f"{rng.randrange(1600000001, 2100000000)},{token}b,Q7,key,MOD,value",
        f"{rng.randrange(1600000001, 2100000000)},{token}c,LM,key,DEL,",
        f"1600000000,{token}d,ZX,key,ADD,1",
        f"notaninteger,{token}e,ZX,key,MOD,1",
        f"{rng.randrange(1600000001, 2100000000)},,ZX,key,ADD,1",
        f"{rng.randrange(1600000001, 2100000000)},{token}f,X,key,ADD,1",
        f"{rng.randrange(1600000001, 2100000000)},{token}g,XYZ,key,ADD,1",
        f"{rng.randrange(1600000001, 2100000000)},{token}h,ZX,key,UPDATE,1",
        f"{rng.randrange(1600000001, 2100000000)},{token}i,ZX,key,ADD",
        f"{rng.randrange(1600000001, 2100000000)},{token}j,ZX,key,ADD,1,extra",
    ]
    rng.shuffle(rows)
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, "input.csv")
        good = os.path.join(td, "good.csv")
        bad = os.path.join(td, "bad.csv")
        with open(inp, "w", newline="") as f:
            f.write("\n".join(rows) + "\n")
        result = run([VALIDATOR, inp, good, bad])
        assert result.returncode == 0, f"validate failed:\n{result.stderr}"
        assert read_lines(good) == [x for x in rows if classify(x)]
        assert read_lines(bad) == [x for x in rows if not classify(x)]
        assert run([VALIDATOR]).returncode != 0
        assert run([VALIDATOR, inp, good]).returncode != 0
        assert run([VALIDATOR, inp, good, bad, os.path.join(td, "extra")]).returncode != 0

    # Replace the source temporarily with an instrumented validator. This checks
    # that pipeline.sh really compiles, splits by region, launches all regional
    # transformations concurrently, waits, and aggregates their actual outputs.
    for path in glob.glob("/tmp/pipeline_active_*") + glob.glob("/tmp/pipeline_seen_*"):
        os.remove(path)
    try:
        os.remove("/tmp/pipeline_concurrency_failed")
    except FileNotFoundError:
        pass

    regions = set()
    while len(regions) < 4:
        regions.add(''.join(rng.choice(string.ascii_uppercase) for _ in range(2)))
    regions = list(regions)
    pipeline_rows = []
    for i, region in enumerate(regions):
        base = rng.randrange(1700000000, 2100000000)
        pipeline_rows.extend([
            f"{base},{token}{i},{region},k{i},ADD,{rng.randrange(10000)}",
            f"{base + 1},{token}{i}x,{region},k{i},DEL,",
            f"1600000000,{token}{i}y,{region},k{i},MOD,bad",
        ])
    rng.shuffle(pipeline_rows)
    with open(SOURCE, "w") as f:
        f.write(INSTRUMENTED_SOURCE)
    with open(STREAM, "w", newline="") as f:
        f.write("\n".join(pipeline_rows) + "\n")
    clean_intermediates()

    result = run([PIPELINE])
    assert result.returncode == 0, f"instrumented pipeline run failed:\n{result.stderr}"
    assert not os.path.exists("/tmp/pipeline_concurrency_failed"), "regional validators were not run concurrently"

    seen_files = glob.glob("/tmp/pipeline_seen_*")
    assert len(seen_files) == 4, f"expected one validator invocation per region, got {len(seen_files)}"
    seen_rows = []
    seen_regions = set()
    for path in seen_files:
        data = read_lines(path)
        assert data, "empty validator invocation log"
        invocation_rows = data[1:]
        assert invocation_rows, "validator received an empty regional split"
        invocation_regions = {line.split(",")[2] for line in invocation_rows}
        assert len(invocation_regions) == 1, "a split file contained multiple regions"
        seen_regions.update(invocation_regions)
        seen_rows.extend(invocation_rows)
    assert seen_regions == set(regions)
    assert collections.Counter(seen_rows) == collections.Counter(pipeline_rows)

    actual_valid = read_lines(os.path.join(HOME, "processed_valid.csv"))
    actual_invalid = read_lines(os.path.join(HOME, "processed_invalid.csv"))
    expected_valid = [x for x in pipeline_rows if classify(x)]
    expected_invalid = [x for x in pipeline_rows if not classify(x)]
    assert collections.Counter(actual_valid) == collections.Counter(expected_valid)
    assert collections.Counter(actual_invalid) == collections.Counter(expected_invalid)
    with open(os.path.join(HOME, "stats.txt")) as f:
        assert f.read().strip() == f"Total Valid: {len(expected_valid)}\nTotal Invalid: {len(expected_invalid)}"
except BaseException as exc:
    failure = exc
finally:
    with open(SOURCE, "wb") as f:
        f.write(original_source)
    with open(STREAM, "wb") as f:
        f.write(original_stream)
    clean_intermediates()
    restore = run([PIPELINE])
    if restore.returncode != 0 and failure is None:
        failure = AssertionError(f"pipeline failed after restoring fixture:\n{restore.stderr}")

if failure is not None:
    raise failure
BEHAVIOR_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import pytest

def test_validate_c_and_executable():
    c_path = "/home/user/validate.c"
    exe_path = "/home/user/validate"

    assert os.path.exists(c_path), f"File {c_path} is missing."
    assert os.path.exists(exe_path), f"File {exe_path} is missing."

    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{exe_path} is not executable."

def test_pipeline_sh_exists_and_contains_keywords():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"File {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "gcc" in content, "pipeline.sh does not contain 'gcc' command."
    assert "&" in content, "pipeline.sh does not use '&' for background tasks."
    assert "wait" in content, "pipeline.sh does not contain 'wait' command."

def test_processed_valid_csv():
    file_path = "/home/user/processed_valid.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    expected_valid = {
        "1612345678,alice,US,max_conn,MOD,100",
        "1612345679,bob,US,timeout,ADD,30",
        "1612345680,dave,US,port,DEL,",
        "1612345681,eve,EU,host,MOD,localhost",
        "1612345684,heidi,EU,ssl,ADD,true",
        "1612345686,judy,AP,log,MOD,debug"
    }

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, f"Expected 6 valid lines, got {len(lines)}."
    assert set(lines) == expected_valid, "Content of processed_valid.csv does not match expected valid lines."

def test_processed_invalid_csv():
    file_path = "/home/user/processed_invalid.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    expected_invalid = {
        "1500000000,charlie,US,retry,MOD,5",
        "1612345682,frank,EU,user,UPDATE,admin",
        "1612345683,grace,E,pass,MOD,secret",
        "1612345685,,AP,cache,MOD,1"
    }

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 invalid lines, got {len(lines)}."
    assert set(lines) == expected_invalid, "Content of processed_invalid.csv does not match expected invalid lines."

def test_stats_txt():
    file_path = "/home/user/stats.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_stats = "Total Valid: 6\nTotal Invalid: 4"
    assert content == expected_stats, f"Content of stats.txt is incorrect. Expected:\n{expected_stats}\nGot:\n{content}"
TEST_EOF

if python3 /tmp/test_behavior.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
