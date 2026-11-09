#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import struct
import tarfile
import secrets
import shutil
import subprocess
import tempfile

import pytest

SOURCE_PATH = '/home/user/extractor.c'
ARCHIVE_PATH = '/home/user/doc_archive.bin'
DOCS_DIR = '/home/user/docs_extracted'


def test_markdown_archive_exists_and_valid():
    tar_path = '/home/user/markdown_archive.tar.gz'
    assert os.path.exists(tar_path), f"Tarball not found at {tar_path}"
    assert os.path.isfile(tar_path), f"{tar_path} is not a file"
    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar file"


def test_markdown_archive_contents():
    tar_path = '/home/user/markdown_archive.tar.gz'
    assert os.path.exists(tar_path), "Tarball not found"

    expected_files = {
        "intro.md": b"# Introduction\nWelcome to the documentation.\n",
        "setup.md": b"## Setup\nRun `make install` to build.\n",
        "api.md": b"### API Reference\n- `get_data()`\n- `set_data()`\n"
    }

    with tarfile.open(tar_path, 'r:gz') as tar:
        names = tar.getnames()
        assert set(names) == set(expected_files.keys()), f"Incorrect files in tarball. Expected {set(expected_files.keys())}, got {set(names)}"

        for name, expected_content in expected_files.items():
            f = tar.extractfile(name)
            assert f is not None, f"Could not extract {name} from tarball"
            content = f.read()
            assert content == expected_content, f"Content of {name} does not match expected output"


def test_docs_extracted_directory():
    docs_extracted_dir = '/home/user/docs_extracted'
    assert os.path.isdir(docs_extracted_dir), f"Directory {docs_extracted_dir} does not exist"

    expected_files = {
        "intro.md": b"# Introduction\nWelcome to the documentation.\n",
        "setup.md": b"## Setup\nRun `make install` to build.\n",
        "api.md": b"### API Reference\n- `get_data()`\n- `set_data()`\n"
    }

    for name, expected_content in expected_files.items():
        file_path = os.path.join(docs_extracted_dir, name)
        assert os.path.exists(file_path), f"File {name} not found in {docs_extracted_dir}"
        with open(file_path, 'rb') as f:
            content = f.read()
            assert content == expected_content, f"Content of {file_path} does not match expected output"


@pytest.fixture(scope='session')
def compiled_extractor(tmp_path_factory):
    assert os.path.exists(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), f"{SOURCE_PATH} is not a regular file"

    with open(SOURCE_PATH, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    assert re.search(r'\bmmap\s*\(', source), "extractor.c does not call mmap"

    build_dir = tmp_path_factory.mktemp('extractor_build')
    executable = build_dir / 'extractor'
    result = subprocess.run(
        ['gcc', '-std=gnu11', '-O0', SOURCE_PATH, '-o', str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"extractor.c did not compile:\n{result.stderr}"
    assert executable.is_file() and os.access(executable, os.X_OK)
    return str(executable), build_dir


def test_compiled_program_handles_fresh_archive_with_mmap(compiled_extractor):
    executable, build_dir = compiled_extractor

    hook_source = build_dir / 'mmap_hook.c'
    hook_library = build_dir / 'mmap_hook.so'
    hook_source.write_text(r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void *(*real_mmap_fn)(void *, size_t, int, int, int, off_t) = 0;

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    if (!real_mmap_fn)
        real_mmap_fn = dlsym(RTLD_NEXT, "mmap");
    if (!real_mmap_fn)
        return MAP_FAILED;

    void *result = real_mmap_fn(addr, length, prot, flags, fd, offset);
    if (result != MAP_FAILED && fd >= 0 && (prot & PROT_READ)) {
        char proc_path[64];
        char target[PATH_MAX + 1];
        snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(proc_path, target, PATH_MAX);
        if (n >= 0) {
            target[n] = '\0';
            if (strcmp(target, "/home/user/doc_archive.bin") == 0) {
                const char *marker = getenv("VERIFIER_MMAP_MARKER");
                if (marker) {
                    int out = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
                    if (out >= 0) {
                        write(out, "mapped\n", 7);
                        close(out);
                    }
                }
            }
        }
    }
    return result;
}
''')
    hook_result = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(hook_source), '-o', str(hook_library), '-ldl'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert hook_result.returncode == 0, f"Could not build mmap verification hook:\n{hook_result.stderr}"

    token = secrets.token_hex(4)
    expected = {
        f'a{token}.md': secrets.token_bytes(37),
        f'b{token}.md': b"dynamic markdown\n" + secrets.token_bytes(19),
    }
    non_markdown = {
        f'c{token}.txt': secrets.token_bytes(29),
    }

    archive = bytearray()
    for name, data in list(expected.items()) + list(non_markdown.items()):
        encoded = name.encode('ascii')
        assert len(encoded) <= 16
        archive.extend(struct.pack('<16sI', encoded.ljust(16, b'\0'), len(data)))
        archive.extend(data)

    with open(ARCHIVE_PATH, 'rb') as f:
        original_archive = f.read()

    backup_dir = None
    marker = str(build_dir / ('mmap_marker_' + secrets.token_hex(8)))
    try:
        if os.path.lexists(DOCS_DIR):
            backup_dir = str(build_dir / 'original_docs')
            os.rename(DOCS_DIR, backup_dir)
        os.makedirs(DOCS_DIR)

        with open(ARCHIVE_PATH, 'wb') as f:
            f.write(archive)

        env = os.environ.copy()
        env['LD_PRELOAD'] = str(hook_library)
        env['VERIFIER_MMAP_MARKER'] = marker
        run = subprocess.run(
            [executable],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f"Compiled extractor failed on a fresh archive:\n{run.stderr}"
        assert os.path.isfile(marker), "Compiled extractor did not mmap /home/user/doc_archive.bin"
        with open(marker, 'rb') as f:
            assert b'mapped\n' in f.read(), "Compiled extractor did not mmap the input archive for reading"

        produced = set(os.listdir(DOCS_DIR))
        assert produced == set(expected), f"Fresh archive extraction produced {produced}, expected {set(expected)}"
        for name, content in expected.items():
            path = os.path.join(DOCS_DIR, name)
            assert os.path.isfile(path), f"Expected extracted file {name} is missing"
            with open(path, 'rb') as f:
                assert f.read() == content, f"Incorrect dynamically generated content for {name}"
    finally:
        with open(ARCHIVE_PATH, 'wb') as f:
            f.write(original_archive)
        if os.path.lexists(DOCS_DIR):
            if os.path.isdir(DOCS_DIR) and not os.path.islink(DOCS_DIR):
                shutil.rmtree(DOCS_DIR)
            else:
                os.unlink(DOCS_DIR)
        if backup_dir is not None and os.path.lexists(backup_dir):
            os.rename(backup_dir, DOCS_DIR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
