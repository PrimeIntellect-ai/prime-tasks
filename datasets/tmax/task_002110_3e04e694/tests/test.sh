#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import builtins
import csv
import io
import os
import pathlib
import random
import runpy
import shutil
import subprocess

import pytest

INDEX_PATH = "/home/user/doc_repo/index.csv"
SCRIPT_PATH = "/home/user/build_index.py"
CONFIG_PATH = "/home/user/doc_repo/config.ini"
DOC_REPO = "/home/user/doc_repo"


def test_index_csv_exists_and_content():
    assert os.path.isfile(INDEX_PATH), f"File {INDEX_PATH} does not exist. Did the script run and create it?"

    expected_content = (
        "Model,MaxTemp,TotalLayers\n"
        "Benchy,215,315\n"
        "CalibCube,200,50\n"
        "VoronPart,255,150"
    )

    with open(INDEX_PATH, "r") as f:
        actual_content = f.read().strip()

    actual_content = actual_content.replace("\r\n", "\n")
    assert actual_content == expected_content, (
        f"Content of {INDEX_PATH} does not match expected output.\n"
        f"Expected:\n{expected_content}\nActual:\n{actual_content}"
    )


def test_script_uses_atomic_write():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    atomic_indicators = ["os.replace", "os.rename", "shutil.move", ".replace(", ".rename("]
    assert any(indicator in content for indicator in atomic_indicators), (
        f"Script {SCRIPT_PATH} does not appear to use an atomic write. "
        "You must write to a temporary file and rename/replace it."
    )


def test_script_executes_streamingly_on_dynamic_fixture_and_replaces_atomically(monkeypatch, tmp_path):
    suffix = str(random.SystemRandom().randrange(100000, 999999))
    models = {
        "Zeta" + suffix: ("gcodes/dynamic_zeta.gcode", 237, 83),
        "Alpha" + suffix: ("gcodes/dynamic_alpha.gcode", None, 14),
        "Middle" + suffix: ("gcodes/dynamic_middle.gcode", 221, None),
    }

    original_config = pathlib.Path(CONFIG_PATH).read_bytes()
    original_index = pathlib.Path(INDEX_PATH).read_bytes()
    created = []

    try:
        pathlib.Path(CONFIG_PATH).write_text(
            "[Models]\n" + "".join(f"{name} = {values[0]}\n" for name, values in models.items()),
            encoding="utf-8",
        )

        fixture_contents = {
            "dynamic_zeta.gcode": (
                "; generated fixture\n"
                "; LAYER_COUNT:83\n"
                "M104 S198\n"
                "G1 X1 Y1\n"
                "M109 S237\n"
                "M104 S225\n"
            ),
            "dynamic_alpha.gcode": (
                "; no hotend target in this file\n"
                "; LAYER_COUNT:14\n"
                "G28\n"
                "G1 X2 Y2\n"
            ),
            "dynamic_middle.gcode": (
                "; no layer count in this file\n"
                "M104 S205\n"
                "M109 S221\n"
            ),
        }
        for filename, content in fixture_contents.items():
            path = pathlib.Path(DOC_REPO, "gcodes", filename)
            path.write_text(content, encoding="utf-8")
            created.append(path)

        sentinel = b"OLD INDEX MUST REMAIN UNTIL ATOMIC REPLACEMENT\n"
        pathlib.Path(INDEX_PATH).write_bytes(sentinel)

        real_builtin_open = builtins.open
        real_io_open = io.open

        class StreamingGuard:
            def __init__(self, wrapped):
                self._wrapped = wrapped

            def read(self, *args, **kwargs):
                raise AssertionError("GCode files must be streamed line-by-line or memory-mapped, not read wholesale")

            def readlines(self, *args, **kwargs):
                raise AssertionError("GCode files must be streamed line-by-line or memory-mapped, not read with readlines()")

            def __iter__(self):
                return self

            def __next__(self):
                return next(self._wrapped)

            def __enter__(self):
                self._wrapped.__enter__()
                return self

            def __exit__(self, *args):
                return self._wrapped.__exit__(*args)

            def __getattr__(self, name):
                return getattr(self._wrapped, name)

        def is_gcode(path):
            try:
                return os.fspath(path).lower().endswith(".gcode")
            except TypeError:
                return False

        def guarded_builtin_open(file, *args, **kwargs):
            result = real_builtin_open(file, *args, **kwargs)
            return StreamingGuard(result) if is_gcode(file) else result

        def guarded_io_open(file, *args, **kwargs):
            result = real_io_open(file, *args, **kwargs)
            return StreamingGuard(result) if is_gcode(file) else result

        monkeypatch.setattr(builtins, "open", guarded_builtin_open)
        monkeypatch.setattr(io, "open", guarded_io_open)

        atomic_events = []
        real_replace = os.replace
        real_rename = os.rename
        real_move = shutil.move

        def record_atomic(src, dst):
            src_abs = os.path.abspath(os.fspath(src))
            dst_abs = os.path.abspath(os.fspath(dst))
            if dst_abs == INDEX_PATH:
                assert src_abs != dst_abs, "Atomic replacement must use a distinct temporary file"
                assert os.path.dirname(src_abs) == DOC_REPO, "Temporary output must be in the same directory as index.csv"
                assert os.path.isfile(src_abs), "Atomic replacement source must be an existing temporary file"
                assert pathlib.Path(INDEX_PATH).read_bytes() == sentinel, (
                    "index.csv was modified or removed before the atomic rename/replace"
                )
                atomic_events.append((src_abs, dst_abs))

        def checked_replace(src, dst, *args, **kwargs):
            record_atomic(src, dst)
            return real_replace(src, dst, *args, **kwargs)

        def checked_rename(src, dst, *args, **kwargs):
            record_atomic(src, dst)
            return real_rename(src, dst, *args, **kwargs)

        def checked_move(src, dst, *args, **kwargs):
            record_atomic(src, dst)
            return real_move(src, dst, *args, **kwargs)

        monkeypatch.setattr(os, "replace", checked_replace)
        monkeypatch.setattr(os, "rename", checked_rename)
        monkeypatch.setattr(shutil, "move", checked_move)

        def no_subprocess(*args, **kwargs):
            raise AssertionError("build_index.py must perform the requested work itself")

        monkeypatch.setattr(os, "system", no_subprocess)
        monkeypatch.setattr(subprocess, "Popen", no_subprocess)
        monkeypatch.setattr(subprocess, "run", no_subprocess)
        monkeypatch.setattr(subprocess, "call", no_subprocess)
        monkeypatch.setattr(subprocess, "check_call", no_subprocess)
        monkeypatch.setattr(subprocess, "check_output", no_subprocess)

        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"build_index.py exited unsuccessfully: {exc.code}"

        assert atomic_events, "The executed script did not atomically rename/replace a same-directory temporary file"
        assert os.path.isfile(INDEX_PATH), "The executed script did not create index.csv"

        with real_builtin_open(INDEX_PATH, "r", newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))

        expected_rows = [["Model", "MaxTemp", "TotalLayers"]]
        for name in sorted(models):
            _, max_temp, layers = models[name]
            expected_rows.append([
                name,
                "None" if max_temp is None else str(max_temp),
                "None" if layers is None else str(layers),
            ])
        assert rows == expected_rows
    finally:
        pathlib.Path(CONFIG_PATH).write_bytes(original_config)
        pathlib.Path(INDEX_PATH).write_bytes(original_index)
        for path in created:
            path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
