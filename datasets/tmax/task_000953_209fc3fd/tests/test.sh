#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

SCRIPT_PATH = "/home/user/archive_filter.py"
PASSWORD = "blue falcon seven"
SIGNATURE = b"BKP_bluefalconseven"


def run_filter(input_dir, output_dir):
    return subprocess.run([
        "python3", SCRIPT_PATH,
        "--input", input_dir,
        "--output", output_dir,
        "--password", PASSWORD,
    ], capture_output=True, text=True, timeout=30)


def assert_exact_hardlinks(input_dir, output_dir, expected_names):
    output_names = {
        os.path.basename(path)
        for path in glob.glob(os.path.join(output_dir, "*.tar"))
    }
    assert output_names == set(expected_names), (
        f"Expected output archives {set(expected_names)}, got {output_names}"
    )

    for name in output_names:
        src = os.path.join(input_dir, name)
        dst = os.path.join(output_dir, name)
        assert os.stat(src).st_ino == os.stat(dst).st_ino, (
            f"File {name} is not a hardlink."
        )


def test_archive_filter_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    clean_input = "/app/corpora/clean"
    evil_input = "/app/corpora/evil"
    clean_output = "/tmp/test_clean"
    evil_output = "/tmp/test_evil"

    shutil.rmtree(clean_output, ignore_errors=True)
    shutil.rmtree(evil_output, ignore_errors=True)
    os.makedirs(clean_output)
    os.makedirs(evil_output)

    res_clean = run_filter(clean_input, clean_output)
    assert res_clean.returncode == 0, f"Script failed on clean corpus:\n{res_clean.stderr}"

    res_evil = run_filter(evil_input, evil_output)
    assert res_evil.returncode == 0, f"Script failed on evil corpus:\n{res_evil.stderr}"

    clean_input_files = [os.path.basename(f) for f in glob.glob(os.path.join(clean_input, "*.tar"))]
    clean_output_files = [os.path.basename(f) for f in glob.glob(os.path.join(clean_output, "*.tar"))]
    missing_clean = set(clean_input_files) - set(clean_output_files)
    assert not missing_clean, (
        f"{len(missing_clean)} of {len(clean_input_files)} clean files were not preserved: {missing_clean}"
    )

    evil_input_files = [os.path.basename(f) for f in glob.glob(os.path.join(evil_input, "*.tar"))]
    evil_output_files = [os.path.basename(f) for f in glob.glob(os.path.join(evil_output, "*.tar"))]
    assert not evil_output_files, (
        f"{len(evil_output_files)} of {len(evil_input_files)} evil files bypassed: {evil_output_files}"
    )

    for name in clean_output_files:
        src = os.path.join(clean_input, name)
        dst = os.path.join(clean_output, name)
        assert os.stat(src).st_ino == os.stat(dst).st_ino, f"File {name} is not a hardlink."


def add_member(tar, kind, name, target=None):
    info = tarfile.TarInfo(name)
    if kind == "file":
        data = ("payload for " + name).encode()
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    elif kind == "symlink":
        info.type = tarfile.SYMTYPE
        info.linkname = target
        tar.addfile(info)
    elif kind == "hardlink":
        info.type = tarfile.LNKTYPE
        info.linkname = target
        tar.addfile(info)
    else:
        raise ValueError(kind)


def make_archive(path, members, signature=SIGNATURE):
    with tarfile.open(path, "w") as tar:
        for member in members:
            add_member(tar, *member)
    with open(path, "ab") as stream:
        stream.write(signature)


def random_tar_name():
    return uuid.uuid4().hex + ".tar"


def test_randomized_mixed_hidden_corpus():
    # This corpus is created only after the agent has finished. Clean and unsafe
    # archives deliberately share one unpredictable input directory, so behavior
    # cannot be selected based on the two public corpus paths.
    with tempfile.TemporaryDirectory(prefix="archive-hidden-") as root:
        input_dir = os.path.join(root, uuid.uuid4().hex)
        output_dir = os.path.join(root, uuid.uuid4().hex)
        os.makedirs(input_dir)
        os.makedirs(output_dir)

        expected = set()

        name = random_tar_name()
        make_archive(os.path.join(input_dir, name), [("file", "data.txt", None)])
        expected.add(name)

        name = random_tar_name()
        make_archive(os.path.join(input_dir, name), [
            ("file", "data.txt", None),
            ("symlink", "alias.txt", "data.txt"),
        ])
        expected.add(name)

        name = random_tar_name()
        make_archive(os.path.join(input_dir, name), [
            ("file", "data.txt", None),
            ("hardlink", "second.txt", "data.txt"),
        ])
        expected.add(name)

        make_archive(os.path.join(input_dir, random_tar_name()), [
            ("file", "../../outside.txt", None),
        ])
        make_archive(os.path.join(input_dir, random_tar_name()), [
            ("file", "/absolute/path.txt", None),
        ])
        make_archive(os.path.join(input_dir, random_tar_name()), [
            ("symlink", "escape", "/root/secret"),
        ])
        make_archive(os.path.join(input_dir, random_tar_name()), [
            ("symlink", "safe/link", "../../outside"),
        ])
        make_archive(os.path.join(input_dir, random_tar_name()), [
            ("hardlink", "safe/link", "../../outside"),
        ])
        make_archive(
            os.path.join(input_dir, random_tar_name()),
            [("file", "ordinary.txt", None)],
            b"BKP_bluefalconseveX",
        )

        malformed = os.path.join(input_dir, random_tar_name())
        with open(malformed, "wb") as stream:
            stream.write(os.urandom(257) + SIGNATURE)

        with open(os.path.join(input_dir, uuid.uuid4().hex + ".txt"), "w") as stream:
            stream.write("not an archive")

        result = run_filter(input_dir, output_dir)
        assert result.returncode == 0, f"Script failed on hidden mixed corpus:\n{result.stderr}"
        assert_exact_hardlinks(input_dir, output_dir, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
