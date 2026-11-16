Allow installing multiple applications with `install` command
**How would this feature be useful?**
Instead of:
```
$pip = @("internetarchive", "git+https://github.com/arecarn/dploy.git", "tubeup")
foreach ($p in $pip) {pipx install $p}
```
I will be able to do just `pipx install internetarchive git+https://github.com/arecarn/dploy.git tubeup`

**Describe the solution you'd like**
Allow installing multiple apps with `pipx install`

**Describe alternatives you've considered**
Using foreach or something like this.

### Additional contract requirements

- On a successful `pipx install` of one or more packages, the command's standard
  output must contain, for each installed package, the text
  `installed package <package_name>`, where `<package_name>` is the resolved
  package name (for example `installed package pycowsay`). A single aggregate
  summary that does not name each installed package does not satisfy this.
- When `venv_dir` is `None`, each package specification must be installed into
  its own separate virtual environment (one venv per package), and the packages
  must be processed sequentially.
- If installing one of several packages fails, `pipx install` reports the failure
  and does not go on to install the remaining packages.
