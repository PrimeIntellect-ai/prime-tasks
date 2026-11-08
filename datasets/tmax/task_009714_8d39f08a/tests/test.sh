#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import functools
import http.server
import os
import shutil
import socketserver
import subprocess
import tempfile
import threading
from pathlib import Path

HOME = Path('/home/user')
BARE = HOME / 'sre-monitor.git'
LOCAL = HOME / 'workspace/monitor_code'
WORKTREE = HOME / 'sre-monitor-src'
BINARY = HOME / 'bin/sre-monitor'
MOUNT = HOME / 'mnt/logs'
POOL = HOME / 'logs_pool'


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 240)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def git(repo, *args):
    return run(['git', '-c', f'safe.directory={repo}', '-C', str(repo), *args])


def reset_mount_dir():
    if MOUNT.is_symlink():
        MOUNT.unlink()
    elif MOUNT.exists():
        shutil.rmtree(MOUNT)
    MOUNT.mkdir(parents=True)


def make_command_mocks(tmpdir):
    tmpdir = Path(tmpdir)
    bind_marker = tmpdir / 'bindfs.args'
    unmount_marker = tmpdir / 'fusermount.args'

    (tmpdir / 'bindfs').write_text(f'''#!/bin/sh
printf '%s\\n' "$@" > "{bind_marker}"
[ "$#" -eq 2 ] || exit 30
[ "$1" = "/home/user/logs_pool" ] || exit 31
[ "$2" = "/home/user/mnt/logs" ] || exit 32
rmdir "$2" || exit 33
ln -s "$1" "$2"
''')
    (tmpdir / 'fusermount').write_text(f'''#!/bin/sh
printf '%s\\n' "$@" > "{unmount_marker}"
[ "$1" = "-u" ] || exit 40
[ "$2" = "/home/user/mnt/logs" ] || exit 41
[ -L "$2" ] || exit 42
rm "$2" && mkdir -p "$2"
''')
    os.chmod(tmpdir / 'bindfs', 0o755)
    os.chmod(tmpdir / 'fusermount', 0o755)
    return bind_marker, unmount_marker


def test_01_storage_configuration_and_mount_script():
    fstab = HOME / 'monitor.fstab'
    assert fstab.exists(), f'{fstab} does not exist.'
    assert fstab.read_text() == '/home/user/logs_pool /home/user/mnt/logs none bind 0 0\n', \
        'monitor.fstab must contain exactly the required single line.'
    assert POOL.is_dir(), f'{POOL} is not a directory.'
    assert MOUNT.is_dir() and not MOUNT.is_symlink(), f'{MOUNT} is not an unmounted directory.'

    mount_script = HOME / 'mount_logs.sh'
    assert mount_script.is_file(), f'{mount_script} does not exist.'
    assert os.access(mount_script, os.X_OK), f'{mount_script} is not executable.'

    reset_mount_dir()
    with tempfile.TemporaryDirectory() as td:
        bind_marker, unmount_marker = make_command_mocks(td)
        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env['PATH']
        run([str(mount_script)], env=env)
        assert bind_marker.read_text().splitlines() == [str(POOL), str(MOUNT)]
        assert MOUNT.is_symlink() and MOUNT.resolve() == POOL.resolve()
        run(['fusermount', '-u', str(MOUNT)], env=env)
        assert unmount_marker.exists()
    assert MOUNT.is_dir() and not MOUNT.is_symlink()


def test_02_git_history_hook_and_real_deployment():
    assert BARE.is_dir(), f'{BARE} does not exist.'
    assert git(BARE, 'rev-parse', '--is-bare-repository').stdout.strip() == 'true'

    hook = BARE / 'hooks/post-receive'
    assert hook.is_file(), f'Git hook {hook} does not exist.'
    assert os.access(hook, os.X_OK), f'Git hook {hook} is not executable.'

    assert (LOCAL / '.git').is_dir(), f'{LOCAL} is not a local Git repository.'
    assert (LOCAL / 'Cargo.toml').is_file()
    assert (LOCAL / 'src/main.rs').is_file()
    assert int(git(LOCAL, 'rev-list', '--count', 'HEAD').stdout.strip()) >= 1
    tracked = git(LOCAL, 'ls-files').stdout.splitlines()
    assert 'Cargo.toml' in tracked and 'src/main.rs' in tracked

    local_head = git(LOCAL, 'rev-parse', 'HEAD').stdout.strip()
    bare_master = git(BARE, 'rev-parse', 'refs/heads/master').stdout.strip()
    assert local_head == bare_master, 'The committed local project was not pushed to bare master.'

    WORKTREE.mkdir(parents=True, exist_ok=True)
    deployed_target = WORKTREE / 'target/release/sre-monitor'
    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    if deployed_target.exists() or deployed_target.is_symlink():
        deployed_target.unlink()
    sentinel = WORKTREE / 'src/main.rs'
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    sentinel.write_text('// verifier sentinel: the hook must check out the pushed tree\n')

    with tempfile.TemporaryDirectory() as td:
        clone = Path(td) / 'push-client'
        run(['git', 'clone', str(BARE), str(clone)])
        git(clone, 'config', 'user.email', 'verifier@example.invalid')
        git(clone, 'config', 'user.name', 'Verifier')
        git(clone, 'commit', '--allow-empty', '-m', 'verifier hook exercise')
        run(['git', '-C', str(clone), 'push', 'origin', 'HEAD:master'])

    assert WORKTREE.is_dir(), 'The hook did not create/use the required work tree.'
    expected_main = git(BARE, 'show', 'master:src/main.rs').stdout
    assert (WORKTREE / 'src/main.rs').read_text() == expected_main, \
        'The hook did not check out the pushed source into sre-monitor-src.'
    assert deployed_target.is_file(), 'cargo build --release did not produce the release binary.'
    assert BINARY.is_file(), f'Binary {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'Binary {BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'The deployed monitor is not a compiled ELF binary.'
    assert BINARY.read_bytes() == deployed_target.read_bytes(), \
        'The hook did not copy the built release binary to /home/user/bin/sre-monitor.'


def serve_status(status):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(status)
            self.end_headers()
            self.wfile.write(b'test')
        def log_message(self, *args):
            pass

    server = socketserver.TCPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def execute_monitor(status):
    log = MOUNT / 'uptime.log'
    if log.exists():
        log.unlink()
    server, thread = serve_status(status)
    try:
        port = server.server_address[1]
        env = os.environ.copy()
        env['MONITOR_URL'] = f'http://127.0.0.1:{port}/probe'
        run([str(BINARY)], env=env, timeout=60)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    assert log.is_file(), 'The deployed binary did not append to the required log file.'
    return log.read_text().strip()


def test_03_deployed_rust_binary_handles_derived_http_results():
    assert MOUNT.is_dir() and not MOUNT.is_symlink()
    assert execute_monitor(200) == 'STATUS: UP'
    assert execute_monitor(503) == 'STATUS: DOWN'


def test_04_execution_wrapper_runs_all_components_and_cleans_up():
    wrapper = HOME / 'run_monitor.sh'
    assert wrapper.is_file(), f'{wrapper} does not exist.'
    assert os.access(wrapper, os.X_OK), f'{wrapper} is not executable.'

    reset_mount_dir()
    pool_log = POOL / 'uptime.log'
    if pool_log.exists():
        pool_log.unlink()

    with tempfile.TemporaryDirectory() as td:
        bind_marker, unmount_marker = make_command_mocks(td)
        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env['PATH']
        run([str(wrapper)], env=env, timeout=90)
        assert bind_marker.read_text().splitlines() == [str(POOL), str(MOUNT)], \
            'run_monitor.sh did not execute mount_logs.sh with the parsed paths.'
        assert unmount_marker.read_text().splitlines() == ['-u', str(MOUNT)], \
            'run_monitor.sh did not unmount the required mount path.'

    assert pool_log.is_file(), f'Log file {pool_log} does not exist.'
    assert 'STATUS: UP' in pool_log.read_text(), f"'STATUS: UP' not found in {pool_log}."
    assert MOUNT.exists(), f'{MOUNT} does not exist.'
    result = subprocess.run(['mountpoint', '-q', str(MOUNT)])
    assert result.returncode != 0, f'{MOUNT} is still mounted. Cleanup was not successful.'
    assert MOUNT.is_dir() and not MOUNT.is_symlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
