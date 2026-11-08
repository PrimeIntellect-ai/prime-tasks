Config file .flake8 not exist when running github actions
### how did you install flake8?

```console
jobs:
  flake8_py3:
    runs-on: ubuntu-latest
    steps:
      - name: Setup Python
        uses: actions/setup-python@v1
        with:
          python-version: 3.9.x
          architecture: x64
      - name: Checkout PyTorch
        uses: actions/checkout@master
      - name: Install flake8
        run: pip install flake8==4.0.1
      - name: Run flake8
        uses: suo/flake8-github-action@v1
        with:
          checkName: 'flake8_py3'   # NOTE: this needs to be the same as the job name
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```


### unmodified output of `flake8 --bug-report`

```json
platform: git hub
```


### describe the problem

# Description of the issue
I have been using flake8 to run during the github  actions. Configuration code is described above in how install flake8.

It was great until the new release 5.0.x was released on the 30th of July.
Starting from this release flake8 always fails because is trying to get the configuration from the runner server, which of course does not exist.


#### what  happen
```
There was a critical error during execution of Flake8:
The specified config file does not exist: /home/runner/work/<my_repository>/.flake8
Error: The process 'flake8' failed with exit code 1

### Additional contract requirements

During automatic configuration discovery, if a candidate cannot be parsed and `.flake8` is absent, Flake8 must not select the nonexistent `.flake8` path and fail while trying to read it. Running Flake8 in that situation must proceed without a discovered configuration file.
