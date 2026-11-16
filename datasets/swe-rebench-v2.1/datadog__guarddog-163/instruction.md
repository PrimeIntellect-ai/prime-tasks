GuardDog should not crash when running only metadata rules
```
$ guarddog pypi scan requests --rules some-metadata-rule
Some rules failed to run while scanning requests:

* rules-all: failed to run rule:
An error occurred when running Semgrep.

command: semgrep --exclude='helm' --exclude='.idea' --exclude='venv' --exclude='test' --exclude='tests' --exclude='.env' --exclude='dist' --exclude='build' --exclude='semgrep' --exclude='migrations' --exclude='.github' --exclude='.semgrep_logs' --no-git-ignore --json --quiet /var/folders/_j/rxmxz87j51q5mzmk79qs0qs00000gp/T/tmp8kfzeyvi/requests
status code: 7
output: {"errors": [{"code": 7, "level": "error", "message": "No config given. Run with `--config auto` or see https://semgrep.dev/docs/running-rules/ for instructions on running with a specific config\n", "type": "SemgrepError"}], "paths": {"_comment": "<add --verbose for a list of skipped paths>", "scanned": []}, "results": [], "version": "0.112.1"}
```
