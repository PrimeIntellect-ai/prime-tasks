#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import importlib.util
import os
import random
import re
import shutil
import subprocess
import sys

import pytest

TRUTH = "1010101110001100101011110000111100110101010001110010101011110000111100110101010001110010101011110000"
OUTPUT_PATH = "/home/user/output.txt"
PROJECT = "/home/user/steg_extractor"
WIDTH = 640
HEIGHT = 480
FRAME_SIZE = WIDTH * HEIGHT


def test_required_source_files_exist():
    for name in ("setup.py", "steg.c", "process.py"):
        path = os.path.join(PROJECT, name)
        assert os.path.isfile(path), f"Required file is missing: {path}"

    c_source = open(os.path.join(PROJECT, "steg.c"), encoding="utf-8").read()
    assert "PyInit_steg" in c_source, "steg.c does not define the Python 3 module initializer PyInit_steg."
    assert "PyModule_Create" in c_source, "steg.c does not use the Python 3 module creation API."
    assert "PyString_" not in c_source, "steg.c still uses the Python 2 PyString API."
    assert not re.search(r"\binitsteg\s*\(", c_source), "steg.c still defines the Python 2 initsteg initializer."

    result = subprocess.run(
        [sys.executable, "-m", "py_compile", os.path.join(PROJECT, "process.py")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"process.py is not valid Python 3:\n{result.stderr}"


@pytest.fixture(scope="session")
def built_extension():
    assert os.path.isfile(os.path.join(PROJECT, "setup.py")), "setup.py is missing."
    assert os.path.isfile(os.path.join(PROJECT, "steg.c")), "steg.c is missing."

    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        for path in glob.glob(os.path.join(PROJECT, "steg*" + suffix)):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        "The C extension did not build cleanly under Python 3.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    candidates = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        candidates.extend(glob.glob(os.path.join(PROJECT, "steg*" + suffix)))
    assert candidates, "Building setup.py did not produce a Python extension module."

    extension_path = max(candidates, key=os.path.getmtime)
    loader = importlib.machinery.ExtensionFileLoader("steg", extension_path)
    spec = importlib.util.spec_from_file_location("steg", extension_path, loader=loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "decode_frame", None)), "The built extension has no decode_frame function."
    return module


def make_frame(block_values, rest_value=73):
    assert len(block_values) == 100
    frame = bytearray([rest_value] * FRAME_SIZE)
    i = 0
    for y in range(10):
        for x in range(10):
            frame[y * WIDTH + x] = block_values[i]
            i += 1
    return bytes(frame)


def generated_cases():
    blocks = [
        [127] * 100,
        [128] * 100,
        [28] + [128] * 99,  # sum 12700: average exactly 127, so result must be 0
        [29] + [128] * 99,  # sum 12701: average strictly greater than 127
        [255] * 50 + [0] * 50,
        [255] * 51 + [0] * 49,
    ]
    rng = random.Random(0x5EEDC0DE)
    for _ in range(24):
        blocks.append([rng.randrange(256) for _ in range(100)])

    cases = []
    for index, block in enumerate(blocks):
        expected = 1 if sum(block) > 127 * 100 else 0
        cases.append((make_frame(block, rest_value=(index * 37 + 19) % 256), expected))
    return cases


def test_c_extension_uses_top_left_block_average(built_extension):
    for index, (frame, expected) in enumerate(generated_cases()):
        actual = built_extension.decode_frame(frame, WIDTH, HEIGHT)
        assert actual == expected, (
            f"decode_frame returned {actual!r} for generated case {index}; "
            f"the top-left 10x10 average requires {expected}."
        )


def test_process_script_processes_binary_frames_sequentially(built_extension):
    cases = generated_cases()
    payload = b"".join(frame for frame, _ in cases) + b"partial-frame"
    expected = "".join(str(bit) for _, bit in cases)
    env = os.environ.copy()
    env["PYTHONPATH"] = PROJECT
    result = subprocess.run(
        [sys.executable, os.path.join(PROJECT, "process.py")],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=PROJECT,
        env=env,
    )
    assert result.returncode == 0, f"process.py failed on raw grayscale frames:\n{result.stderr.decode(errors='replace')}"
    assert result.stdout == expected.encode("ascii"), (
        "process.py did not emit exactly one continuous bit per complete input frame, "
        "or emitted extra text/newlines."
    )


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}. Did you run the extraction and save the output?"


def read_output():
    data = open(OUTPUT_PATH, "rb").read()
    assert data, "Output file is empty."
    try:
        return data.decode("ascii")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Output is not ASCII: {exc}")


def test_output_file_accuracy():
    output = read_output()
    assert len(output) == len(TRUTH), f"Output length is {len(output)}, but expected exactly {len(TRUTH)} bits."
    matches = sum(1 for a, b in zip(TRUTH, output) if a == b)
    accuracy = matches / len(TRUTH)
    assert accuracy >= 0.95, f"Accuracy is {accuracy:.4f} (Threshold: >= 0.95). The extracted bits do not match the ground truth closely enough."


def test_output_contains_only_binary_and_no_trailing_newline():
    output = read_output()
    invalid_chars = set(output) - {'0', '1'}
    assert not invalid_chars, f"Output contains invalid characters: {invalid_chars}. It should only contain '0' and '1'."
    assert not output.endswith(("\n", "\r")), "Output must not contain a trailing newline."


def test_evidence_pipeline_reproduces_saved_output(built_extension):
    env = os.environ.copy()
    env["PYTHONPATH"] = PROJECT
    ffmpeg = subprocess.Popen(
        [
            "ffmpeg", "-v", "error", "-i", "/app/evidence.mp4",
            "-vf", "fps=10", "-f", "rawvideo", "-pix_fmt", "gray", "-"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    process = subprocess.Popen(
        [sys.executable, os.path.join(PROJECT, "process.py")],
        stdin=ffmpeg.stdout,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=PROJECT,
        env=env,
    )
    assert ffmpeg.stdout is not None
    ffmpeg.stdout.close()
    process_out, process_err = process.communicate()
    ffmpeg_err = ffmpeg.stderr.read() if ffmpeg.stderr is not None else b""
    ffmpeg_rc = ffmpeg.wait()
    assert ffmpeg_rc == 0, f"ffmpeg frame extraction failed:\n{ffmpeg_err.decode(errors='replace')}"
    assert process.returncode == 0, f"process.py failed on evidence frames:\n{process_err.decode(errors='replace')}"
    saved = open(OUTPUT_PATH, "rb").read()
    assert process_out == saved, "Running ffmpeg at 10 fps through process.py does not reproduce output.txt exactly."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
