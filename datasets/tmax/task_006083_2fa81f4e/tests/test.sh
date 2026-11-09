#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

SCRIPT = Path('/home/user/check_convergence.sh')
DATA = Path('/home/user/data')
SIM = Path('/home/user/bin/run_sim.sh')
LOG = Path('/home/user/diverged_sims.log')


def test_check_convergence_script_exists_and_executable():
    script_path = '/home/user/check_convergence.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_diverged_sims_log_contents():
    log_path = '/home/user/diverged_sims.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the script?"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ['protein_B.fasta', 'protein_D.fasta']

    assert lines == expected_lines, (
        f"Contents of {log_path} are incorrect.\n"
        f"Expected: {expected_lines}\n"
        f"Found: {lines}"
    )


def test_script_executes_and_handles_dynamic_fasta_inputs():
    token = uuid.uuid4().hex[:10]
    fixtures = {
        f'a_{token}.fasta': ('>first dynamic\nMA\nCCCC\n', 'MACCCC'),
        f'k_{token}.fasta': ('>first only\nMNN\nPP\n>second must be ignored\nCCCCCC\n', 'MNNPP'),
        f'q_{token}.fasta': ('>final-step test\nMCC\n', 'MCC'),
        f't_{token}.fasta': ('>threshold test\nRIGID\n', 'RIGID'),
        f'z_{token}.fasta': ('>another divergent input\nQQ\nQ\n', 'QQQ'),
    }
    final_values = {
        'MACCCC': 1000.25,
        'MNNPP': 12.5,
        'MCC': 999.0,
        'RIGID': 1000.0,
        'QQQ': 2500.75,
    }

    with tempfile.TemporaryDirectory() as td:
        backup = Path(td)
        shutil.copytree(DATA, backup / 'data')
        shutil.copy2(SIM, backup / 'run_sim.sh')
        log_existed = LOG.exists()
        if log_existed:
            shutil.copy2(LOG, backup / 'diverged_sims.log')

        call_log = Path(f'/tmp/run_sim_calls_{token}.log')
        try:
            shutil.rmtree(DATA)
            DATA.mkdir(parents=True)
            # Create in reverse order so filesystem creation order cannot satisfy the test.
            for name in reversed(list(fixtures)):
                (DATA / name).write_text(fixtures[name][0])

            mock = f'''#!/bin/bash
printf '%s|%s\\n' "$#" "$1" >> "{call_log}"
case "$1" in
  MACCCC) final=1000.25 ;;
  MNNPP) final=12.5 ;;
  MCC) final=999.0 ;;
  RIGID) final=1000.0 ;;
  QQQ) final=2500.75 ;;
  *) echo "unexpected sequence" >&2; exit 91 ;;
esac
echo "Step 1: 10"
echo "Step 2: 5000"
echo "Step 3: 20"
echo "Step 4: 30"
echo "Step 5: $final"
'''
            SIM.write_text(mock)
            SIM.chmod(0o755)
            if LOG.exists():
                LOG.unlink()
            if call_log.exists():
                call_log.unlink()

            result = subprocess.run(
                [str(SCRIPT)],
                cwd='/home/user',
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert result.returncode == 0, (
                f"check_convergence.sh failed with status {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            ordered_names = sorted(fixtures)
            expected_calls = [f"1|{fixtures[name][1]}" for name in ordered_names]
            assert call_log.is_file(), "The simulation script was not invoked."
            actual_calls = call_log.read_text().splitlines()
            assert actual_calls == expected_calls, (
                "FASTA files were not processed alphabetically, the first sequences "
                "were not parsed correctly, or run_sim.sh did not receive one argument.\n"
                f"Expected calls: {expected_calls}\nFound calls: {actual_calls}"
            )

            expected_log = [
                name for name in ordered_names
                if final_values[fixtures[name][1]] > 1000
            ]
            assert LOG.is_file(), "Running the script did not generate diverged_sims.log."
            actual_log = LOG.read_text().splitlines()
            assert actual_log == expected_log, (
                "The generated divergence log is incorrect. Divergence must be based "
                "only on the final Step value being greater than 1000.\n"
                f"Expected: {expected_log}\nFound: {actual_log}"
            )
        finally:
            if call_log.exists():
                call_log.unlink()
            if DATA.exists():
                shutil.rmtree(DATA)
            shutil.copytree(backup / 'data', DATA)
            shutil.copy2(backup / 'run_sim.sh', SIM)
            if log_existed:
                shutil.copy2(backup / 'diverged_sims.log', LOG)
            elif LOG.exists():
                LOG.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
