`reinstall` is destructive when misused with local source directory
<!--
Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can.

Please check pipx's Troubleshooting page to see if any of those solutions help solve your issue:
https://pipx.pypa.io/stable/troubleshooting/
-->

pipx version 1.5.0

**Describe the bug**

I have a package installed with pipx, and I wanted to reinstall it from a local source repository. I ran

```bash
pipx reinstall {absolute-path-to-repo}
```

thinking that it would do something equivalent to

```bash
pipx install {absolute-path-to-repo} --force
```

Instead, it deleted the file tree at `{absolute-path-to-repo}`.

From this experience, I have inferred that I have misunderstood the intended functionality and arguments of the `reinstall` command. (I'm inferring that reinstall accepts a path to a package's pipx virtual environment, rather than a path to package source.) However, I feel like this is an easy mistake to make, and the destructive side effect of this performing this action seems really bad. I did in fact lose some work that was only in my local git repository.

**How to reproduce**

1. Create any directory
    ```bash
    mkdir testdir
    ```
2. Run `pipx reinstall` with an absolute path to that directory
    ```bash
    pipx reinstall $(pwd)/testdir
    ```
    This produces output
    ```
    uninstalled testdir! ✨ 🌟 ✨
    Fatal error from pip prevented installation. Full pip output in file:
        /Users/jqi/.local/pipx/logs/cmd_2024-04-05_19.03.13_pip_errors.log

    Some possibly relevant errors from pip install:
        ERROR: Could not find a version that satisfies the requirement testdir (from versions: none)
        ERROR: No matching distribution found for testdir

    Error installing testdir.
    ```
    with the side effect of deleting `testdir/`.

**Expected behavior**

`pipx reinstall` should not accept a local file path as an argument to prevent misuse. Or if this is actually desired functionality, there should more checks in place to ensure that it is intentional and actually a path to a pipx virtual environment.
