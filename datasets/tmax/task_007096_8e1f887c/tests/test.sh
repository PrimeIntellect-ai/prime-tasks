#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_publish.py
import fcntl
import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/publish.sh')
DOCS = Path('/home/user/docs_draft')
RELEASES = Path('/home/user/releases')


def test_script_exists_and_executable():
    path = '/home/user/publish.sh'
    assert os.path.isfile(path), f'Script {path} does not exist.'
    assert os.access(path, os.X_OK), f'Script {path} is not executable.'


def test_script_uses_flock():
    path = '/home/user/publish.sh'
    with open(path, 'r') as f:
        content = f.read()
    assert 'flock' in content, "The script does not use 'flock' as required."


def test_markdown_contents():
    doc1_v1 = '/home/user/releases/v1.0/doc1.md'
    doc1_v2 = '/home/user/releases/v1.1/doc1.md'

    assert os.path.isfile(doc1_v1), f'{doc1_v1} does not exist.'
    assert os.path.isfile(doc1_v2), f'{doc1_v2} does not exist.'

    with open(doc1_v1, 'r') as f:
        lines1 = f.read().strip().split('\n')
    assert lines1[-1] == 'Status: PUBLISHED', f"{doc1_v1} does not end with 'Status: PUBLISHED'"

    with open(doc1_v2, 'r') as f:
        content2 = f.read()
        lines2 = content2.strip().split('\n')
    assert lines2[-1] == 'Status: PUBLISHED', f"{doc1_v2} does not end with 'Status: PUBLISHED'"
    assert 'Extra line' in content2, f"{doc1_v2} does not contain 'Extra line'"


def test_hardlinks():
    img1_v1 = '/home/user/releases/v1.0/img1.png'
    img1_v2 = '/home/user/releases/v1.1/img1.png'

    assert os.path.isfile(img1_v1), f'{img1_v1} does not exist.'
    assert os.path.isfile(img1_v2), f'{img1_v2} does not exist.'

    stat1 = os.stat(img1_v1)
    stat2 = os.stat(img1_v2)
    assert stat1.st_ino == stat2.st_ino, f'{img1_v1} and {img1_v2} are not hardlinked (different inodes).'


def test_img2_exists():
    img2_v1 = '/home/user/releases/v1.0/img2.png'
    img2_v2 = '/home/user/releases/v1.1/img2.png'

    assert not os.path.exists(img2_v1), f'{img2_v1} should not exist in v1.0 release.'
    assert os.path.isfile(img2_v2), f'{img2_v2} does not exist in v1.1 release.'


def test_symlink_latest():
    latest = '/home/user/releases/latest'
    assert os.path.islink(latest), f'{latest} is not a symlink.'

    target = os.path.realpath(latest)
    expected_target = '/home/user/releases/v1.1'
    assert target == expected_target, f'Symlink {latest} points to {target}, expected {expected_target}.'


def run_script(*args, timeout=15):
    return subprocess.run(
        [str(SCRIPT), *args], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )


def start_script(release):
    return subprocess.Popen(
        [str(SCRIPT), release], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def finish(proc, timeout=15):
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        pytest.fail(f'publish.sh timed out. stdout={out!r}, stderr={err!r}')
    assert proc.returncode == 0, f'publish.sh failed with {proc.returncode}. stdout={out!r}, stderr={err!r}'


def expected_markdown(source):
    data = source.read_bytes()
    if not data.endswith(b'\n'):
        data += b'\n'
    return data + b'Status: PUBLISHED\n'


def assert_release(release, markdown_sources, png_names):
    directory = RELEASES / release
    assert directory.is_dir(), f'{directory} was not created'
    expected_names = set(markdown_sources) | set(png_names)
    assert {p.name for p in directory.iterdir()} == expected_names
    for name, source in markdown_sources.items():
        assert (directory / name).read_bytes() == expected_markdown(source)
    for name in png_names:
        assert (directory / name).is_file()


def test_dynamic_execution_arguments_contents_links_and_locking():
    # Exercise the submitted artifact on verifier-generated data rather than
    # trusting only the final state left by the agent.
    shutil.rmtree(DOCS, ignore_errors=True)
    shutil.rmtree(RELEASES, ignore_errors=True)
    DOCS.mkdir(parents=True)
    RELEASES.mkdir(parents=True)
    os.chmod(DOCS, 0o777)
    os.chmod(RELEASES, 0o777)

    token = uuid.uuid4().hex
    first = f'check-{token[:10]}-a'
    second = f'check-{token[:10]}-b'
    concurrent_a = f'check-{token[:10]}-c'
    concurrent_b = f'check-{token[:10]}-d'

    doc1 = DOCS / 'doc1.md'
    doc2 = DOCS / f'doc2_{token[:8]}.md'
    img1 = DOCS / f'image_{token[:8]}.png'
    doc1.write_text(f'generated title {token}\ngenerated body one\n')
    doc2.write_text(f'second generated document {token}\n')
    img1.write_bytes((f'png-one-{token}\n').encode())

    # Exactly one argument is required, and invalid invocations must not publish.
    no_arg = run_script()
    assert no_arg.returncode != 0, 'publish.sh accepted zero arguments'
    two_args = run_script(first, second)
    assert two_args.returncode != 0, 'publish.sh accepted two arguments'
    assert not (RELEASES / first).exists()
    assert not (RELEASES / second).exists()
    assert not (RELEASES / 'latest').exists()

    # Hold the required lock before starting the script. A conforming script must
    # wait and must not begin creating the release while another publisher owns it.
    lock_path = RELEASES / '.lock'
    lock_file = open(lock_path, 'a+')
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = start_script(first)
    time.sleep(0.6)
    assert proc.poll() is None, 'publish.sh did not wait for /home/user/releases/.lock'
    assert not (RELEASES / first).exists(), 'publishing began while another process held the lock'
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()
    finish(proc)

    sources_first = {doc1.name: doc1, doc2.name: doc2}
    assert_release(first, sources_first, [img1.name])
    assert (RELEASES / first / img1.name).read_bytes() == img1.read_bytes()
    assert os.stat(RELEASES / first / img1.name).st_ino != os.stat(img1).st_ino
    assert (RELEASES / 'latest').is_symlink()
    assert (RELEASES / 'latest').resolve() == (RELEASES / first).resolve()

    old_img_bytes = (RELEASES / first / img1.name).read_bytes()
    doc1.write_text(doc1.read_text() + f'changed-{token}\n')
    doc2.write_text(doc2.read_text() + f'doc2-change-{token}\n')
    # Existing PNGs must come from latest even if the draft with that name changes.
    img1.write_bytes((f'changed-draft-image-{token}\n').encode())
    img2 = DOCS / f'new_image_{token[:8]}.png'
    img2.write_bytes((f'new-png-{token}\n').encode())

    result = run_script(second)
    assert result.returncode == 0, f'publish.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
    sources_second = {doc1.name: doc1, doc2.name: doc2}
    assert_release(second, sources_second, [img1.name, img2.name])
    assert (RELEASES / second / img1.name).read_bytes() == old_img_bytes
    assert os.stat(RELEASES / first / img1.name).st_ino == os.stat(RELEASES / second / img1.name).st_ino
    assert (RELEASES / second / img2.name).read_bytes() == img2.read_bytes()
    assert os.stat(RELEASES / second / img2.name).st_ino != os.stat(img2).st_ino
    assert (RELEASES / 'latest').is_symlink()
    assert (RELEASES / 'latest').resolve() == (RELEASES / second).resolve()

    # Start two CI-style invocations while the lock is owned externally. Both must
    # wait, then complete successfully and produce full releases once serialized.
    lock_file = open(lock_path, 'a+')
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc_a = start_script(concurrent_a)
    proc_b = start_script(concurrent_b)
    time.sleep(0.6)
    assert proc_a.poll() is None and proc_b.poll() is None
    assert not (RELEASES / concurrent_a).exists()
    assert not (RELEASES / concurrent_b).exists()
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()
    finish(proc_a)
    finish(proc_b)

    assert_release(concurrent_a, sources_second, [img1.name, img2.name])
    assert_release(concurrent_b, sources_second, [img1.name, img2.name])
    latest_target = (RELEASES / 'latest').resolve()
    assert latest_target in {(RELEASES / concurrent_a).resolve(), (RELEASES / concurrent_b).resolve()}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_publish.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
