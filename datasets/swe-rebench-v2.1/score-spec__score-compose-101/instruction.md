[feature request] add --no-sample option for score-compose init
When score-compose is being used in a directory which already has a score file but it's not named `score.yaml` it may be useful to skip generating the default score.yaml file to avoid creating confusion and garbage.

For example if I have a monorepo with 2 score projects `frontend/score.yaml` and `backend/score.yaml` I don't want an additional score.yaml file to be created in the top level directory so I should run `score-compose init --no-sample` which will avoid the sample being generated.

### Additional contract requirements

`--no-sample` suppresses only generation of the default sample Score file. Initialization must still perform its other normal work, including setting up project state and the default provisioner configuration.
