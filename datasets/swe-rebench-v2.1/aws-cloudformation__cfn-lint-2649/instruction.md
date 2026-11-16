ValueError: list.remove(x): x not in list
### CloudFormation Lint Version

0.76.0

### What operating system are you using?

macOS

### Describe the bug

We run `cfn-lint` on all templates in the [AWS SAM repository](https://github.com/aws/serverless-application-model/).

Since today `cfn-lint` fails with:

```text
Traceback (most recent call last):
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/bin/cfn-lint", line 8, in <module>
    sys.exit(main())
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/__main__.py", line 39, in main
    matches = list(cfnlint.core.get_matches(filenames, args))
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/core.py", line 173, in get_matches
    matches = run_cli(
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/core.py", line 78, in run_cli
    return run_checks(filename, template, rules, regions, mandatory_rules)
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/core.py", line 334, in run_checks
    runner = cfnlint.runner.Runner(
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/runner.py", line 32, in __init__
    self.cfn = Template(filename, template, regions)
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/template/template.py", line 44, in __init__
    self.conditions = cfnlint.conditions.Conditions(self)
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/conditions/conditions.py", line 34, in __init__
    self._cnf, self._solver_params = self._build_cnf(list(self._conditions.keys()))
  File "/Users/rehnc/Desktop/tmp/serverless-application-model/.venv_cfn_lint/lib/python3.10/site-packages/cfnlint/conditions/conditions.py", line 118, in _build_cnf
    allowed_values[param.hash].remove(get_hash(equal_1.left))
ValueError: list.remove(x): x not in list
```

### Expected behavior

Expected it not to fail, or to fail like a template violation would.

### Reproduction template

Not sure yet which one is causing the issue, but this reproduces it:

```bash
git clone https://github.com/aws/serverless-application-model.git --depth 1
cd serverless-application-model
python3 -m venv .venv
pip install cfn-lint
.venv/bin/cfn-lint
```

### Additional contract requirements

- For the template with `Environment` allowed values `prod`, `dev`, and `stage`, where `IsGamma` compares `Environment` to `gamma` and `IsBeta` compares `beta` to `Environment`, `Conditions.build_scenarios(["IsGamma", "IsBeta"])` must return `[ {"IsBeta": false, "IsGamma": false} ]`, and `Conditions.build_scenarios(["IsGamma"])` must return `[ {"IsGamma": false} ]`.
