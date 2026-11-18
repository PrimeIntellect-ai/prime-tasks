#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/legacy_api.py /tmp/legacy_api.py.verifier_backup
cp /home/user/new_api.py /tmp/new_api.py.verifier_backup
restore_apis() {
    cp /tmp/legacy_api.py.verifier_backup /home/user/legacy_api.py
    cp /tmp/new_api.py.verifier_backup /home/user/new_api.py
}
trap restore_apis EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import shutil
import subprocess
import time
from pathlib import Path

SCRIPT = Path('/home/user/run_e2e.sh')
REPORT = Path('/home/user/test_report.txt')
LEGACY = Path('/home/user/legacy_api.py')
NEW = Path('/home/user/new_api.py')
MARKERS = Path('/tmp/e2e_verifier_events.jsonl')
VENV = Path('/home/user/venv')


def test_run_e2e_script_exists_and_executable():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'


def process_matches(pattern):
    try:
        result = subprocess.run(['pgrep', '-f', pattern], capture_output=True, text=True)
        return result.returncode == 0
    except FileNotFoundError:
        result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
        return any(pattern in line and 'grep' not in line for line in result.stdout.splitlines())


def assert_servers_stopped():
    deadline = time.time() + 3
    while time.time() < deadline:
        if not process_matches('legacy_api.py') and not process_matches('new_api.py'):
            return
        time.sleep(0.1)
    assert not process_matches('legacy_api.py'), 'legacy_api.py process is still running; it was not cleaned up.'
    assert not process_matches('new_api.py'), 'new_api.py process is still running; it was not cleaned up.'


def marker_code():
    return '''
def mark(event, **fields):
    import json, os, time
    fields.update(event=event, time=time.time(), pid=os.getpid())
    fd = os.open('/tmp/e2e_verifier_events.jsonl', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (json.dumps(fields) + "\\n").encode())
    finally:
        os.close(fd)
'''


def install_instrumented_apis(legacy_response, new_response):
    legacy_source = '''import sys\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\n''' + marker_code() + f'''
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        mark('legacy_get', path=self.path)
        if self.path == '/api/data':
            body = {legacy_response!r}.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass
if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    mark('legacy_start', port=port, argv=sys.argv, executable=sys.executable)
    HTTPServer(('127.0.0.1', port), Handler).serve_forever()
'''
    new_source = '''import sys\nfrom flask import Flask, Response\n''' + marker_code() + f'''
app = Flask(__name__)
@app.route('/api/data', methods=['GET'])
def data():
    mark('new_get', path='/api/data')
    return Response({new_response!r}, mimetype='application/json')
if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    mark('new_start', port=port, argv=sys.argv, executable=sys.executable, prefix=sys.prefix)
    app.run(host='127.0.0.1', port=port, use_reloader=False)
'''
    LEGACY.write_text(legacy_source)
    NEW.write_text(new_source)


def run_submission(expected_report, legacy_response, new_response):
    install_instrumented_apis(legacy_response, new_response)
    REPORT.unlink(missing_ok=True)
    MARKERS.unlink(missing_ok=True)

    runuser = shutil.which('runuser')
    if runuser:
        command = [runuser, '-u', 'user', '--', str(SCRIPT)]
        result = subprocess.run(command, cwd='/home/user', capture_output=True, text=True, timeout=120)
    else:
        account = pwd.getpwnam('user')
        def demote():
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        result = subprocess.run([str(SCRIPT)], cwd='/home/user', capture_output=True,
                                text=True, timeout=120, preexec_fn=demote)

    assert result.returncode != 124, 'run_e2e.sh timed out.'
    assert REPORT.is_file(), 'run_e2e.sh did not create /home/user/test_report.txt.'
    content = REPORT.read_text().strip()
    assert content == expected_report, (
        f'Expected a freshly generated {expected_report} report, got {content!r}. '
        f'stdout={result.stdout!r} stderr={result.stderr!r}'
    )

    assert MARKERS.is_file(), 'The API programs were not started and exercised.'
    events = [json.loads(line) for line in MARKERS.read_text().splitlines() if line.strip()]
    names = [event['event'] for event in events]
    for required in ('legacy_start', 'new_start', 'legacy_get', 'new_get'):
        assert required in names, f'Missing observed API event: {required}; events={events!r}'

    legacy_start = next(e for e in events if e['event'] == 'legacy_start')
    new_start = next(e for e in events if e['event'] == 'new_start')
    assert legacy_start['port'] == 8080, 'legacy_api.py was not started on port 8080.'
    assert new_start['port'] == 8081, 'new_api.py was not started on port 8081.'
    assert Path(new_start['prefix']).resolve() == VENV.resolve(), 'new_api.py was not run from /home/user/venv.'
    assert any(e['event'] == 'legacy_get' and e['path'] == '/api/data' for e in events), 'Legacy /api/data was not requested.'
    assert any(e['event'] == 'new_get' and e['path'] == '/api/data' for e in events), 'New /api/data was not requested.'
    assert names.index('legacy_get') < names.index('new_get'), 'The legacy API must be requested before the new API.'
    assert_servers_stopped()


def test_script_performs_end_to_end_comparison_and_cleanup():
    assert_servers_stopped()
    shutil.rmtree(VENV, ignore_errors=True)

    matching = '{"status": "success", "data": {"items": [1, 2, 3, 4, 5], "metadata": "legacy"}}'
    different = '{"status": "success", "data": {"items": [1, 2, 3, 4, 5], "metadata": "different"}}'

    run_submission('FAIL', matching, different)
    assert VENV.is_dir(), 'The script did not create /home/user/venv.'
    python = VENV / 'bin/python'
    assert python.is_file(), 'The virtual environment has no Python executable.'
    flask_check = subprocess.run(
        [str(python), '-c', 'import flask; print(flask.__version__ if hasattr(flask, "__version__") else "ok")'],
        capture_output=True, text=True
    )
    assert flask_check.returncode == 0, f'Flask is not installed in the virtual environment: {flask_check.stderr}'

    run_submission('PASS', matching, matching)


def test_report_file_content():
    assert REPORT.is_file(), f'Report file {REPORT} does not exist.'
    content = REPORT.read_text().strip()
    assert content == 'PASS', f"Expected report content to be 'PASS', but got '{content}'."


def test_servers_are_cleaned_up():
    assert_servers_stopped()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
