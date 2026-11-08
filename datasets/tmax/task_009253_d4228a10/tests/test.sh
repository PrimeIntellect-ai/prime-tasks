#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

HOME = Path('/home/user')
ARCHIVE = HOME / 'docs_archive.tar'
CLEAN = HOME / 'clean_docs'
LOG = HOME / 'malicious_paths.txt'
MASTER = HOME / 'master_doc.md'


def test_malicious_paths_log():
    log_path = "/home/user/malicious_paths.txt"
    assert os.path.isfile(log_path), f"Log file {log_path} not found."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_paths = [
        "../home/user/.bashrc",
        "/etc/shadow",
        "docs/../../etc/passwd"
    ]

    assert lines == expected_paths, f"Expected malicious paths {expected_paths}, but got {lines}."


def test_clean_docs_extracted():
    clean_docs_dir = "/home/user/clean_docs"
    assert os.path.isdir(clean_docs_dir), f"Directory {clean_docs_dir} not found."

    expected_files = {
        "intro.md": "# Introduction\nWelcome to the docs.",
        "setup.md": "# Setup\nRun install.",
        "api/reference.md": "# API\nList of endpoints.",
        "appendix.md": "# Appendix\nExtra details."
    }

    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(clean_docs_dir, rel_path)
        assert os.path.isfile(full_path), f"Safe file {full_path} was not extracted."
        with open(full_path, "r") as f:
            content = f.read()
            assert content == expected_content, f"Content of {full_path} is incorrect."

    actual_files = set()
    actual_dirs = set()
    for root, dirs, files in os.walk(clean_docs_dir, followlinks=False):
        rel_root = os.path.relpath(root, clean_docs_dir)
        for name in dirs:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink in clean_docs: {path}"
            rel = name if rel_root == "." else os.path.join(rel_root, name)
            actual_dirs.add(rel)
        for name in files:
            path = os.path.join(root, name)
            assert not os.path.islink(path), f"Unexpected symlink in clean_docs: {path}"
            rel = name if rel_root == "." else os.path.join(rel_root, name)
            actual_files.add(rel)
    assert actual_files == set(expected_files), f"Unexpected files in clean_docs: {actual_files - set(expected_files)}"
    assert actual_dirs == {"api"}, f"Unexpected directories in clean_docs: {actual_dirs}"


def test_master_doc_content():
    master_doc_path = "/home/user/master_doc.md"
    assert os.path.isfile(master_doc_path), f"Master doc {master_doc_path} not found."

    expected_content = (
        "# Appendix\nExtra details.\n\n"
        "# Introduction\nWelcome to the docs.\n\n"
        "# API\nList of endpoints."
    )

    with open(master_doc_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Master doc content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_original_payloads_were_not_written_outside_clean_docs():
    forbidden = {
        Path('/home/user/.bashrc'): b"alias ls='rm -rf'",
        Path('/home/user/home/user/.bashrc'): b"alias ls='rm -rf'",
        Path('/etc/shadow'): b"root:*:18900:0:99999:7:::",
        Path('/home/user/etc/passwd'): b"root:x:0:0:root:/root:/bin/bash",
        Path('/etc/passwd'): b"root:x:0:0:root:/root:/bin/bash",
    }
    for path, payload in forbidden.items():
        if path.is_file():
            assert path.read_bytes() != payload, f"Archive payload was written outside clean_docs: {path}"


def add_file(tar, name, content, timestamp):
    info = tarfile.TarInfo(name=name)
    data = content.encode('utf-8')
    info.size = len(data)
    info.mtime = int(datetime.strptime(timestamp, '%Y-%m-%d %H:%M:%S').replace(tzinfo=timezone.utc).timestamp())
    tar.addfile(info, BytesIO(data))


def home_snapshot():
    result = {}
    excluded = {ARCHIVE, LOG, MASTER}
    if not HOME.exists():
        return result
    for path in HOME.rglob('*'):
        if path == CLEAN or CLEAN in path.parents or path in excluded:
            continue
        if '__pycache__' in path.parts:
            continue
        rel = str(path.relative_to(HOME))
        if path.is_symlink():
            result[rel] = ('link', os.readlink(path))
        elif path.is_file():
            result[rel] = ('file', hashlib.sha256(path.read_bytes()).hexdigest())
    return result


def find_candidate_scripts():
    candidates = []
    verifier_path = Path(__file__).resolve()
    for base in (Path('/home/user'), Path('/root'), Path('/tmp')):
        if not base.exists():
            continue
        for path in base.rglob('*.py'):
            try:
                if path.resolve() == verifier_path or CLEAN in path.parents or not path.is_file() or path.is_symlink():
                    continue
                text = path.read_text(errors='ignore')
            except (OSError, PermissionError):
                continue
            if 'docs_archive.tar' in text or ('malicious_paths.txt' in text and 'clean_docs' in text):
                candidates.append(path)
    return sorted(set(candidates), key=lambda p: p.stat().st_mtime_ns, reverse=True)


def validate_dynamic_result(expected_files, expected_malicious, expected_master, outside_targets, before):
    assert LOG.is_file(), 'Dynamic run did not create malicious_paths.txt'
    assert LOG.read_text().splitlines() == expected_malicious, 'Dynamic malicious path log is incorrect'
    assert CLEAN.is_dir(), 'Dynamic run did not create clean_docs'

    actual_files = set()
    actual_dirs = set()
    for root, dirs, files in os.walk(CLEAN, followlinks=False):
        root_path = Path(root)
        for name in dirs:
            path = root_path / name
            assert not path.is_symlink(), f'Extracted an unexpected symlink: {path}'
            actual_dirs.add(str(path.relative_to(CLEAN)))
        for name in files:
            path = root_path / name
            assert path.is_file() and not path.is_symlink(), f'Extracted a non-regular file: {path}'
            rel = str(path.relative_to(CLEAN))
            actual_files.add(rel)
            assert path.read_text() == expected_files[rel], f'Wrong dynamic content for {rel}'

    assert actual_files == set(expected_files), f'Dynamic extraction has missing or unexpected files: {actual_files}'
    expected_dirs = {str(Path(name).parent) for name in expected_files if Path(name).parent != Path('.')}
    assert actual_dirs == expected_dirs, f'Dynamic extraction has unexpected directories: {actual_dirs}'
    assert MASTER.is_file(), 'Dynamic run did not create master_doc.md'
    assert MASTER.read_text().strip() == expected_master.strip(), 'Dynamic merged document is incorrect'

    for target in outside_targets:
        assert not target.exists(), f'Archive member escaped clean_docs and wrote {target}'
    assert home_snapshot() == before, 'The sanitizer changed or created files outside its permitted outputs'


def test_script_exists_and_handles_derived_archive_safely():
    candidates = find_candidate_scripts()
    assert candidates, 'No sanitizing Python script was found'

    token = secrets.token_hex(8)
    abs_target = Path('/tmp') / f'tar_slip_{token}.txt'
    rel_target = HOME / f'tar_slip_{token}.txt'
    rel_target2 = HOME / f'tar_slip_nested_{token}.txt'
    malicious = [
        f'../tar_slip_{token}.txt',
        str(abs_target),
        f'nested/../../tar_slip_nested_{token}.txt',
    ]
    expected_files = {
        f'alpha_{token}.md': f'ALPHA-{token}',
        f'nested/zeta_{token}.md': f'ZETA-{token}',
        f'odd..name_{token}.md': f'ODD-{token}',
        f'old_{token}.md': f'OLD-{token}',
        f'notes_{token}.txt': f'NOTES-{token}',
    }
    expected_master = '\n\n'.join([
        expected_files[f'alpha_{token}.md'],
        expected_files[f'odd..name_{token}.md'],
        expected_files[f'nested/zeta_{token}.md'],
    ])
    outside_targets = [abs_target, rel_target, rel_target2]
    original_archive = ARCHIVE.read_bytes()
    errors = []

    try:
        for candidate in candidates:
            shutil.rmtree(CLEAN, ignore_errors=True)
            for path in (LOG, MASTER, *outside_targets):
                try:
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
                except FileNotFoundError:
                    pass

            with tarfile.open(ARCHIVE, 'w') as tar:
                add_file(tar, f'nested/zeta_{token}.md', expected_files[f'nested/zeta_{token}.md'], '2025-07-04 10:00:00')
                add_file(tar, malicious[0], 'ESCAPE-ONE', '2025-07-04 10:00:00')
                add_file(tar, f'old_{token}.md', expected_files[f'old_{token}.md'], '2022-12-31 23:59:59')
                add_file(tar, f'alpha_{token}.md', expected_files[f'alpha_{token}.md'], '2024-02-03 10:00:00')
                add_file(tar, malicious[1], 'ESCAPE-TWO', '2025-07-04 10:00:00')
                add_file(tar, f'odd..name_{token}.md', expected_files[f'odd..name_{token}.md'], '2026-01-02 10:00:00')
                add_file(tar, f'notes_{token}.txt', expected_files[f'notes_{token}.txt'], '2026-01-02 10:00:00')
                add_file(tar, malicious[2], 'ESCAPE-THREE', '2025-07-04 10:00:00')

            before = home_snapshot()
            try:
                proc = subprocess.run(
                    ['python3', str(candidate)], cwd='/home/user',
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
                )
                assert proc.returncode == 0, f'exited {proc.returncode}: {proc.stderr[-500:]}'
                validate_dynamic_result(expected_files, malicious, expected_master, outside_targets, before)
                return
            except Exception as exc:
                errors.append(f'{candidate}: {exc}')

        assert False, 'No discovered Python script passed a derived archive test. ' + ' | '.join(errors)
    finally:
        ARCHIVE.write_bytes(original_archive)
        for path in outside_targets:
            try:
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
