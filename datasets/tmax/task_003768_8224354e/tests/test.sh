#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
ANALYZER = HOME / 'analyzer'
SOURCE = HOME / 'analyzer.cpp'
REPO = HOME / 'cloud_repo'
BACKUP = HOME / 'cloud_backup.tar.gz'
SERVICE = HOME / 'start_service.sh'
REPORT = HOME / 'cost_report.txt'
HOOK_LOG = HOME / 'hook_log.txt'


def run(cmd, **kwargs):
    kwargs.setdefault('stdout', subprocess.PIPE)
    kwargs.setdefault('stderr', subprocess.PIPE)
    kwargs.setdefault('timeout', 20)
    return subprocess.run(cmd, **kwargs)


def save_file(path):
    return path.read_bytes() if path.exists() else None


def restore_file(path, data):
    if path.exists() or path.is_symlink():
        path.unlink()
    if data is not None:
        path.write_bytes(data)


def test_analyzer_compiled():
    assert SOURCE.is_file(), f'Analyzer source not found at {SOURCE}'
    assert ANALYZER.is_file(), f'Analyzer executable not found at {ANALYZER}'
    assert os.access(ANALYZER, os.X_OK), f'Analyzer is not executable: {ANALYZER}'
    with ANALYZER.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{ANALYZER} is not a valid ELF executable'

    # Ensure the supplied source itself is compilable, then exercise the submitted
    # artifact under both dependency states described by that source.
    with tempfile.TemporaryDirectory() as td:
        reference = Path(td) / 'reference_analyzer'
        result = run(['g++', str(SOURCE), '-o', str(reference)])
        assert result.returncode == 0, result.stderr.decode(errors='replace')

    saved_report = save_file(REPORT)
    parked_repo = HOME / ('.verifier_repo_' + next(tempfile._get_candidate_names()))
    assert REPO.is_dir(), f'Repository directory not found at {REPO}'
    os.rename(REPO, parked_repo)
    try:
        if REPORT.exists():
            REPORT.unlink()
        missing = run([str(ANALYZER)])
        assert missing.returncode == 1, 'Analyzer must fail when cloud_repo is absent'
        assert not REPORT.exists(), 'Analyzer produced a report despite the missing dependency'

        REPO.mkdir()
        present = run([str(ANALYZER)])
        assert present.returncode == 0, present.stderr.decode(errors='replace')
        assert REPORT.is_file(), 'Analyzer did not generate the cost report'
        assert REPORT.read_text().strip() == 'ANALYSIS_COMPLETE', 'Analyzer generated an incorrect report'
    finally:
        if REPO.exists():
            shutil.rmtree(REPO)
        os.rename(parked_repo, REPO)
        restore_file(REPORT, saved_report)


def test_start_service_script():
    assert SERVICE.is_file(), f'Service script not found at {SERVICE}'
    assert os.access(SERVICE, os.X_OK), f'Service script is not executable: {SERVICE}'
    content = SERVICE.read_text()
    assert 'cloud_repo' in content, 'Script does not check for cloud_repo'
    assert 'tar' in content, 'Script does not contain tar extraction command'
    assert 'exit 2' in content or 'exit  2' in content, 'Script does not exit with code 2 on tar failure'
    assert '/home/user/analyzer' in content, 'Script does not execute the analyzer'

    parked_analyzer = HOME / ('.verifier_analyzer_' + next(tempfile._get_candidate_names()))
    marker = HOME / ('.verifier_service_marker_' + next(tempfile._get_candidate_names()))
    os.rename(ANALYZER, parked_analyzer)
    ANALYZER.write_text('#!/bin/sh\nprintf "CALLED\\n" >> ' + str(marker) + '\n')
    ANALYZER.chmod(0o755)
    try:
        # An existing repository must bypass restoration and invoke the analyzer.
        result = run([str(SERVICE)])
        assert result.returncode == 0, 'Service failed when cloud_repo already existed'
        assert marker.read_text() == 'CALLED\n', 'Service did not execute /home/user/analyzer'
        marker.unlink()

        # With the repository absent, the real backup must be restored before the
        # analyzer is invoked.
        parked_repo = HOME / ('.verifier_service_repo_' + next(tempfile._get_candidate_names()))
        os.rename(REPO, parked_repo)
        try:
            result = run([str(SERVICE)])
            assert result.returncode == 0, result.stderr.decode(errors='replace')
            assert (REPO / '.git').is_dir(), 'Service did not restore cloud_repo from the backup'
            assert marker.read_text() == 'CALLED\n', 'Service did not invoke the analyzer after restoration'
        finally:
            if REPO.exists():
                shutil.rmtree(REPO)
            os.rename(parked_repo, REPO)
            if marker.exists():
                marker.unlink()

        # A failed extraction must return exactly 2 and must not run the analyzer.
        parked_repo = HOME / ('.verifier_failure_repo_' + next(tempfile._get_candidate_names()))
        parked_backup = HOME / ('.verifier_backup_' + next(tempfile._get_candidate_names()))
        os.rename(REPO, parked_repo)
        os.rename(BACKUP, parked_backup)
        BACKUP.write_bytes(b'not a tar archive')
        try:
            result = run([str(SERVICE)])
            assert result.returncode == 2, f'Extraction failure returned {result.returncode}, expected 2'
            assert not marker.exists(), 'Analyzer ran even though backup extraction failed'
        finally:
            if REPO.exists():
                shutil.rmtree(REPO)
            os.rename(parked_repo, REPO)
            if BACKUP.exists():
                BACKUP.unlink()
            os.rename(parked_backup, BACKUP)
    finally:
        if ANALYZER.exists():
            ANALYZER.unlink()
        os.rename(parked_analyzer, ANALYZER)
        if marker.exists():
            marker.unlink()


def test_cloud_repo_restored_and_updated():
    assert REPO.is_dir(), f'Repository directory not found at {REPO}'
    assert (REPO / '.git').is_dir(), f'Not a valid git repository: {REPO}'
    new_resource = REPO / 'new_resource.json'
    assert new_resource.is_file(), f'new_resource.json not found in {REPO}'
    assert new_resource.stat().st_size == 0, 'new_resource.json is not empty'

    result = run(['git', 'ls-files', '--error-unmatch', 'new_resource.json'], cwd=REPO)
    assert result.returncode == 0, 'new_resource.json is not tracked by git'

    result = run(['git', 'log', '-1', '--pretty=%B'], cwd=REPO, text=True)
    assert 'Add new resource' in result.stdout, 'Latest commit does not have the expected message'

    result = run(['git', 'diff-tree', '--no-commit-id', '--name-status', '-r', 'HEAD'], cwd=REPO, text=True)
    assert any(line.split('\t') == ['A', 'new_resource.json'] for line in result.stdout.splitlines()), \
        'Latest commit did not add new_resource.json'


def test_git_hook():
    hook = REPO / '.git/hooks/post-commit'
    assert hook.is_file(), f'Git hook not found at {hook}'
    assert os.access(hook, os.X_OK), f'Git hook is not executable: {hook}'
    content = hook.read_text()
    assert 'HOOK_FIRED' in content, "Git hook does not contain the text 'HOOK_FIRED'"
    assert '/home/user/analyzer' in content, 'Git hook does not execute the analyzer'

    # Trigger the installed hook through Git while replacing the analyzer with a
    # probe. Restore HEAD and all user-visible files after the behavioral check.
    old_head = run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).stdout.strip()
    saved_log = save_file(HOOK_LOG)
    parked_analyzer = HOME / ('.verifier_hook_analyzer_' + next(tempfile._get_candidate_names()))
    marker = HOME / ('.verifier_hook_marker_' + next(tempfile._get_candidate_names()))
    os.rename(ANALYZER, parked_analyzer)
    ANALYZER.write_text('#!/bin/sh\nprintf "CALLED\\n" >> ' + str(marker) + '\n')
    ANALYZER.chmod(0o755)
    generated_log = None
    generated_marker = None
    commit_result = None
    try:
        if HOOK_LOG.exists():
            HOOK_LOG.unlink()
        commit_result = run(['git', 'commit', '--allow-empty', '-m', 'Verifier hook test'], cwd=REPO)
        if HOOK_LOG.exists():
            generated_log = HOOK_LOG.read_bytes()
        if marker.exists():
            generated_marker = marker.read_bytes()
    finally:
        run(['git', 'reset', '--hard', old_head], cwd=REPO)
        if ANALYZER.exists():
            ANALYZER.unlink()
        os.rename(parked_analyzer, ANALYZER)
        restore_file(HOOK_LOG, saved_log)
        if marker.exists():
            marker.unlink()

    assert commit_result.returncode == 0, commit_result.stderr.decode(errors='replace')
    assert generated_log in (b'HOOK_FIRED', b'HOOK_FIRED\n'), 'Hook did not append exactly HOOK_FIRED'
    assert generated_marker == b'CALLED\n', 'Git hook did not execute /home/user/analyzer'


def test_hook_log():
    assert HOOK_LOG.is_file(), f'Hook log file not found at {HOOK_LOG}'
    assert 'HOOK_FIRED' in HOOK_LOG.read_text(), "Hook log does not contain 'HOOK_FIRED'"


def test_cost_report():
    assert REPORT.is_file(), f'Cost report not found at {REPORT}'
    assert 'ANALYSIS_COMPLETE' in REPORT.read_text(), "Cost report does not contain 'ANALYSIS_COMPLETE'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
