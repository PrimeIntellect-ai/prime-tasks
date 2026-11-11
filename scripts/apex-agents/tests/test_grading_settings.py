"""Exercise the grader's credential handoff using a real child process."""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
GRADERS = sorted((ROOT / "datasets/apex-agents").glob("*/tests/grade.py"))
spec = importlib.util.spec_from_file_location("apex_grade", GRADERS[0])
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)

# Mirror the upstream runner's file-based CLI contract, including opening the
# grading-settings path in the child, rather than mocking subprocess.run.
RUNNER = """
import json
import os
import sys
from pathlib import Path

args = dict(zip(sys.argv[1::2], sys.argv[2::2], strict=True))
with open(args['--grading-settings']) as handle:
    settings = json.load(handle)
assert settings == json.loads(os.environ['EXPECTED_GRADING_SETTINGS'])
assert not Path(args['--output']).with_name('grading_settings.json').exists()
if os.environ.get('FAIL_GRADING'):
    sys.exit(7)
Path(args['--output']).write_text(json.dumps({
    'grading_run_status': 'completed',
    'scoring_results': {'final_score': 1.0},
}))
"""


class GradingSettingsTests(unittest.TestCase):
    def run_grader(self, settings, expected, *, fail=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = root / "runner"
            runner.mkdir()
            (runner / "__init__.py").touch()
            (runner / "main.py").write_text(RUNNER)
            workdir = root / "work"
            workdir.mkdir()
            trajectory = root / "trajectory.json"
            trajectory.write_text(json.dumps({
                "messages": [{"role": "assistant", "content": "Done"}],
            }))
            config = {
                "grading_settings": settings,
                "verifiers": [],
                "eval_configs": [],
                "scoring_config": {},
            }
            env = {
                "LITELLM_PROXY_API_KEY": "test-proxy-credential",
                "LITELLM_PROXY_API_BASE": "https://proxy.example.test/v1",
                "GRADING_MODEL": "openai/test-judge",
                "EXPECTED_GRADING_SETTINGS": json.dumps(expected),
            }
            if fail:
                env["FAIL_GRADING"] = "1"
            with patch.dict(os.environ, env, clear=True), patch.multiple(
                grade,
                GRADING_PROJECT=root,
                GRADING_PYTHON=Path(sys.executable),
                TRAJECTORY=trajectory,
                INITIAL_SNAPSHOT=root / "initial.tar.gz",
                FINAL_SNAPSHOT=root / "final.tar.gz",
                GOLDEN_DIR=root / "golden",
            ):
                if fail:
                    with self.assertRaisesRegex(grade.GradingError, "exited 7"):
                        grade.run_grading(config, workdir)
                    self.assertFalse((workdir / "grades.json").exists())
                else:
                    result = grade.run_grading(config, workdir)
                    self.assertEqual(result["scoring_results"]["final_score"], 1.0)
            self.assertFalse((workdir / "grading_settings.json").exists())
            for path in workdir.iterdir():
                for credential in (b"test-proxy-credential", b"test-config-credential"):
                    self.assertNotIn(credential, path.read_bytes(), str(path))

    def test_proxy_settings_reach_runner_without_a_credential_file(self):
        self.run_grader({}, {
            "llm_judge_model": "openai/test-judge",
            "llm_judge_extra_args": {
                "api_key": "test-proxy-credential",
                "api_base": "https://proxy.example.test/v1",
            },
        })

    def test_explicit_settings_take_precedence_and_large_input_does_not_block(self):
        extra = {
            "api_key": "test-config-credential",
            "api_base": "https://configured.example.test/v1",
            "metadata": "x" * 70000,
        }
        self.run_grader({
            "llm_judge_model": "original-model",
            "llm_judge_extra_args": extra,
        }, {
            "llm_judge_model": "openai/test-judge",
            "llm_judge_extra_args": extra,
        })

    def test_runner_failure_still_surfaces(self):
        self.run_grader({}, {
            "llm_judge_model": "openai/test-judge",
            "llm_judge_extra_args": {
                "api_key": "test-proxy-credential",
                "api_base": "https://proxy.example.test/v1",
            },
        }, fail=True)

    def test_all_task_graders_share_the_tested_implementation(self):
        self.assertEqual(len(GRADERS), 240)
        for path in GRADERS:
            self.assertEqual(path.read_bytes(), GRADERS[0].read_bytes(), str(path))


if __name__ == "__main__":
    unittest.main()
