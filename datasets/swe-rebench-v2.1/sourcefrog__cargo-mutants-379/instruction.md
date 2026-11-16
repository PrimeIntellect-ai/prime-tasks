Clean warning and success if the `--in-diff` diff file is empty?
I think in https://github.com/sourcefrog/conserve/actions/runs/8676081693/job/23790302177 the diff was empty and mutants failed, which is probably not what you want.

### Additional contract requirements

- When the `--in-diff` file is empty, the command must succeed, list no mutants, and write a message containing `diff file is empty` to stderr.
