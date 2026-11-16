fail fast does not stop command execution once the `BEFORE` command fails
```
[BEFORE] [kiegroup/kogito-runtimes] bash -c "if [ ! -z 'quarkus-3' ] && [ -f .ci/environments/update.sh ]; then .ci/environments/update.sh quarkus-3 rewrite push_changes; fi"

[INFO] NOT OK [Executed in 1235095.288113 ms]

[ERROR] The process '/usr/bin/bash' failed with exit code 1

[COMMANDS] [kiegroup/kogito-runtimes] export MVN_CMD=`bash -c "if [ 'true' = 'true' ]; then printf 'deploy  -DaltDeploymentRepository=local::default::file:///home/jenkins/workspace/KIE/kogito/main/nightly.quarkus-3/drools.integration/maven_deploy_dir '; else printf 'install'; fi"`

[INFO] OK [Executed in 6.868972 ms]
```

build-chain should have stopped execution after before failed

### Additional contract requirements

- When fail-fast stops execution, report `ExecutionResult.SKIP` for each unexecuted phase. If the `BEFORE` phase fails, the phase results must be `[ExecutionResult.NOT_OK, ExecutionResult.SKIP, ExecutionResult.SKIP]`.
