#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import random
import stat
import string
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import pytest

MAGIC = b"CFG_TRACKER_V1\0\0"
EXECUTABLE = "/home/user/cfg_filter"
SOURCE = "/home/user/cfg_filter.c"


def run_filter(executable, path):
    try:
        return subprocess.run(
            [executable, path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {path}")


def rand_name(suffix=""):
    alphabet = string.ascii_lowercase
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(12)) + suffix


def make_tar(entries):
    """entries are (kind, archive_name, data_or_link_target)."""
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tf:
        for kind, name, value in entries:
            info = tarfile.TarInfo(name)
            info.mtime = random.randint(1, 2_000_000_000)
            if kind == "file":
                data = value
                info.size = len(data)
                info.mode = 0o600
                tf.addfile(info, io.BytesIO(data))
            elif kind == "dir":
                info.type = tarfile.DIRTYPE
                info.mode = 0o700
                info.size = 0
                tf.addfile(info)
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = value
                info.size = 0
                tf.addfile(info)
            else:
                raise AssertionError(kind)
    return out.getvalue()


def make_zip(entries):
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries:
            zf.writestr(name, data)
    return out.getvalue()


def cfg(payload, magic=MAGIC):
    return magic + payload


def test_cfg_filter_exists_and_executable():
    assert os.path.isfile(EXECUTABLE), f"Missing executable: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    assert not os.path.islink(EXECUTABLE), "cfg_filter must be a compiled executable, not a symlink"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cfg_filter is not an ELF executable"

    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    assert not os.path.islink(SOURCE), "cfg_filter.c must be a regular source file"


def test_generated_archives_and_c_source():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    with tempfile.TemporaryDirectory(prefix="cfg-verifier-") as td:
        rebuilt = os.path.join(td, rand_name())
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", rebuilt, "-larchive"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert compiled.returncode == 0, (
            "cfg_filter.c did not compile with libarchive:\n"
            + compiled.stderr.decode(errors="replace")
        )
        assert os.access(rebuilt, os.X_OK)

        safe_file = rand_name(".txt")
        safe_dir = rand_name()
        simple_clean = make_tar([
            ("dir", safe_dir + "/", b""),
            ("file", safe_dir + "/" + safe_file, os.urandom(37)),
        ])
        empty_clean = make_tar([])

        nested_one = make_tar([
            ("file", rand_name(".txt"), os.urandom(19)),
        ])
        nested_two = make_tar([
            ("file", rand_name(".tar.gz"), nested_one),
        ])
        nested_three = make_tar([
            ("file", rand_name(".tar.gz"), nested_two),
        ])

        clean_zip = make_zip([(rand_name(".txt"), os.urandom(23))])
        evil_zip = make_zip([(rand_name() + "/../../" + rand_name(".txt"), b"escape")])

        cases = [
            (cfg(empty_clean), 0, "valid empty archive"),
            (cfg(simple_clean), 0, "valid files and directories"),
            (cfg(make_tar([("file", rand_name(".tar.gz"), nested_one)])), 0,
             "one nested tar archive"),
            (cfg(make_tar([("file", rand_name(".tar.gz"), nested_two)])), 0,
             "two nested tar archives"),
            (cfg(make_tar([("file", rand_name(".zip"), clean_zip)])), 0,
             "valid nested zip archive"),
            (cfg(make_tar([("file", "../" + rand_name(), b"x")])), 1,
             "parent traversal path"),
            (cfg(make_tar([("file", rand_name() + "/../" + rand_name(), b"x")])), 1,
             "embedded parent traversal path"),
            (cfg(make_tar([("file", "/" + rand_name(), b"x")])), 1,
             "absolute path"),
            (cfg(make_tar([("symlink", rand_name(), "/" + rand_name())])), 1,
             "absolute symlink target"),
            (cfg(make_tar([("symlink", rand_name(), "../" + rand_name())])), 1,
             "traversing symlink target"),
            (cfg(make_tar([("file", rand_name(".tar.gz"), nested_three)])), 1,
             "three nested archives"),
            (cfg(make_tar([("file", rand_name(".tar.gz"),
                            make_tar([("file", "../" + rand_name(), b"x")]))])), 1,
             "traversal inside nested tar"),
            (cfg(make_tar([("file", rand_name(".zip"), evil_zip)])), 1,
             "traversal inside nested zip"),
            (cfg(make_tar([("file", rand_name(".tar.gz"), os.urandom(41))])), 1,
             "corrupt nested archive"),
            (cfg(os.urandom(53)), 1, "corrupt main payload"),
            (MAGIC, 1, "missing main payload"),
            (cfg(simple_clean, b"BAD_TRACKER_V1!!"), 1, "invalid magic"),
            (MAGIC[:9], 1, "truncated magic"),
        ]
        random.SystemRandom().shuffle(cases)

        paths = []
        for data, expected, description in cases:
            case_dir = os.path.join(td, rand_name())
            os.mkdir(case_dir)
            path = os.path.join(case_dir, rand_name(".cfg"))
            with open(path, "wb") as f:
                f.write(data)
            paths.append((path, expected, description))

        for executable in (EXECUTABLE, rebuilt):
            for path, expected, description in paths:
                actual = run_filter(executable, path)
                assert actual == expected, (
                    f"{executable} returned {actual}, expected {expected}, "
                    f"for {description}"
                )

        # Preserve checks of the shipped adversarial corpus. These placeholder
        # files have no valid tar.gz payload, so all are corrupt under the task rules.
        corpus_files = []
        for directory in (clean_dir, evil_dir):
            corpus_files.extend(
                os.path.join(directory, name)
                for name in os.listdir(directory)
                if os.path.isfile(os.path.join(directory, name))
            )
        assert corpus_files, "Shipped corpus is empty"
        for path in corpus_files:
            assert run_filter(EXECUTABLE, path) == 1, (
                f"Corrupt shipped corpus file was not rejected: {path}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
