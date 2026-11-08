#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

HOME = Path('/home/user')
BARE = HOME / 'restore_deploy.git'
WORKSPACE = HOME / 'workspace'
STAGING = HOME / 'deploy_staging'
PRODUCTION = HOME / 'production_restore'
HOOK = BARE / 'hooks' / 'post-receive'


def run(cmd, *, cwd=None, env=None, check=True):
    return subprocess.run(
        cmd, cwd=cwd, env=env, check=check, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )


def git(args, *, cwd=None):
    return run(['git', '-c', 'safe.directory=*'] + args, cwd=cwd)


def test_complete_deployment_pipeline():
    # Preserve the original final-state assertions.
    bashrc = HOME / '.bashrc'
    assert bashrc.is_file(), f'{bashrc} does not exist.'
    assert 'export BACKUP_ENV_ACTIVE=1' in bashrc.read_text(), \
        '.bashrc does not contain the required export statement.'

    assert BARE.is_dir(), f'Bare repo {BARE} does not exist.'
    assert (BARE / 'objects').is_dir(), f'{BARE} does not look like a bare git repo.'
    assert git(['rev-parse', '--is-bare-repository'], cwd=BARE).stdout.strip() == 'true'

    assert HOOK.is_file(), f'Hook {HOOK} does not exist.'
    hook_stat = HOOK.stat()
    assert hook_stat.st_mode & stat.S_IXUSR, f'Hook {HOOK} is not executable.'
    assert stat.S_ISREG(HOOK.lstat().st_mode), 'post-receive must be a regular file.'

    assert STAGING.is_dir(), f'Staging directory {STAGING} does not exist.'
    staged_bin = STAGING / 'restore_bin'
    assert staged_bin.is_file(), f'Compiled binary {staged_bin} does not exist.'
    assert staged_bin.stat().st_mode & stat.S_IXUSR, f'Binary {staged_bin} is not executable.'

    assert PRODUCTION.is_dir(), f'Restore directory {PRODUCTION} does not exist.'
    for filename in ('data1.bin', 'data2.bin'):
        restored = PRODUCTION / filename
        assert restored.is_file(), f'Restored file {restored} does not exist.'
        assert restored.read_text() == 'RESTORED_SUCCESS\n', \
            f'File {restored} does not contain the correct content.'

    assert WORKSPACE.is_dir(), f'Workspace {WORKSPACE} does not exist.'
    assert (WORKSPACE / '.git').is_dir(), f'{WORKSPACE} is not a git repository.'
    index_file = WORKSPACE / 'backup_index.txt'
    source_file = WORKSPACE / 'restore_sim.c'
    assert index_file.is_file(), f'{index_file} does not exist.'
    assert source_file.is_file(), f'{source_file} does not exist.'
    assert index_file.read_bytes() == b'data1.bin\ndata2.bin\n'

    # Validate repository history, branch, remote, and committed artifacts.
    assert git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd=WORKSPACE).stdout.strip() == 'master'
    origin = git(['remote', 'get-url', 'origin'], cwd=WORKSPACE).stdout.strip()
    assert os.path.realpath(origin) == str(BARE), 'origin does not point to the required bare repository.'
    workspace_head = git(['rev-parse', 'HEAD'], cwd=WORKSPACE).stdout.strip()
    bare_master = git(['rev-parse', 'refs/heads/master'], cwd=BARE).stdout.strip()
    assert workspace_head == bare_master, 'The workspace master commit was not pushed to origin.'
    committed = set(git(['ls-tree', '-r', '--name-only', 'HEAD'], cwd=WORKSPACE).stdout.splitlines())
    assert {'backup_index.txt', 'restore_sim.c'} <= committed
    assert git(['show', 'HEAD:backup_index.txt'], cwd=WORKSPACE).stdout == 'data1.bin\ndata2.bin\n'
    assert git(['show', 'HEAD:restore_sim.c'], cwd=WORKSPACE).stdout.encode() == source_file.read_bytes()

    # Exercise the submitted C source independently with an alternate index and RESTORE_DIR.
    with tempfile.TemporaryDirectory(prefix='restore-program-') as td:
        td = Path(td)
        binary = td / 'restore_bin'
        run(['gcc', str(source_file), '-o', str(binary)])
        case_dir = td / 'case'
        case_dir.mkdir()
        names = [f'alt_{uuid.uuid4().hex}.bin', f'alt_{uuid.uuid4().hex}.dat']
        (case_dir / 'backup_index.txt').write_text('\n'.join(names) + '\n')

        no_env = os.environ.copy()
        no_env.pop('RESTORE_DIR', None)
        result = run([str(binary)], cwd=case_dir, env=no_env, check=False)
        assert result.returncode == 1, 'restore_sim must exit with code 1 when RESTORE_DIR is unset.'

        alternate_restore = td / 'restore target'
        with_env = os.environ.copy()
        with_env['RESTORE_DIR'] = str(alternate_restore)
        result = run([str(binary)], cwd=case_dir, env=with_env, check=False)
        assert result.returncode == 0, result.stderr
        assert alternate_restore.is_dir()
        assert stat.S_IMODE(alternate_restore.stat().st_mode) == 0o755
        for name in names:
            assert (alternate_restore / name).read_bytes() == b'RESTORED_SUCCESS\n'

    # Check that the hook describes the required pipeline, then trigger it with a
    # fresh commit whose source and output cannot be satisfied by fixed artifacts.
    hook_text = HOOK.read_text(errors='replace')
    for required in ('RESTORE_DIR', '/home/user/production_restore',
                     '/home/user/deploy_staging', 'restore_sim.c', 'restore_bin'):
        assert required in hook_text, f'post-receive does not reference {required!r}.'
    assert 'gcc' in hook_text or 'cc' in hook_text, 'post-receive does not invoke a C compiler.'

    nonce = uuid.uuid4().hex
    dynamic_name = f'hook_{nonce}.bin'
    dynamic_text = f'HOOK_EXECUTED_{nonce}\\n'
    dynamic_source = f'''#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
int main(void) {{
    const char *dir = getenv("RESTORE_DIR");
    char path[4096];
    FILE *f;
    if (!dir) return 1;
    if (mkdir(dir, 0755) != 0 && errno != EEXIST) return 2;
    if (snprintf(path, sizeof(path), "%s/{dynamic_name}", dir) >= (int)sizeof(path)) return 3;
    f = fopen(path, "w");
    if (!f) return 4;
    if (fputs("{dynamic_text}", f) == EOF) return 5;
    if (fclose(f) != 0) return 6;
    return 0;
}}
'''

    with tempfile.TemporaryDirectory(prefix='hook-push-') as td:
        clone = Path(td) / 'clone'
        git(['clone', str(BARE), str(clone)])
        (clone / 'backup_index.txt').write_text(dynamic_name + '\n')
        (clone / 'restore_sim.c').write_text(dynamic_source)
        git(['add', 'backup_index.txt', 'restore_sim.c'], cwd=clone)
        git(['-c', 'user.name=Verifier', '-c', 'user.email=verifier@local',
             'commit', '-m', f'verifier hook exercise {nonce}'], cwd=clone)
        pushed_commit = git(['rev-parse', 'HEAD'], cwd=clone).stdout.strip()

        # Remove all prior staging artifacts so the push must check out and compile.
        shutil.rmtree(STAGING)
        STAGING.mkdir(mode=0o755)
        dynamic_output = PRODUCTION / dynamic_name
        if dynamic_output.exists():
            dynamic_output.unlink()

        git(['push', 'origin', 'HEAD:master'], cwd=clone)

        assert git(['rev-parse', 'refs/heads/master'], cwd=BARE).stdout.strip() == pushed_commit
        assert (STAGING / 'backup_index.txt').read_text() == dynamic_name + '\n'
        assert (STAGING / 'restore_sim.c').read_text() == dynamic_source
        rebuilt = STAGING / 'restore_bin'
        assert rebuilt.is_file() and rebuilt.stat().st_mode & stat.S_IXUSR
        assert rebuilt.read_bytes()[:4] == b'\x7fELF', 'Hook did not produce a compiled executable.'
        assert dynamic_output.is_file(), 'The pushed program was not executed by the hook.'
        assert dynamic_output.read_text() == dynamic_text

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
