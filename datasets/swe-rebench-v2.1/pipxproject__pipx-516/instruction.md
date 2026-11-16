Installation not pulling in optional extras-requires packages.
(Full disclosure, this issue is occurring after an OS upgrade, though I've uninstalled and re-installed pipx) -- great tool by the way!!

I have a project on Bitbucket (private). I have historically installed locally with pipx;
`pipx install "my-project[cli] @ git+ssh://git@bitbucket.org/my-company/myproject.git"`

The setup.cfg for the project has an install-requires of
`[options.extras_require]`
```
cli =
    begins
    docker
```

Installing goes smoothly, but the `begins` and `docker` packages do not install. I verify by looking within `/home/steve/.local/pipx/venvs/my-project/lib/python/site-packages`

[pipx-verbose.txt](https://github.com/pipxproject/pipx/files/5330613/pipx-verbose.txt)



**Expected behavior**
Historically, this would have correctly detected the [cli] designation and installed the appropriate packages. I'm not sure if this has to do with a recent upgrade or something is broken on my end.

If it is an issue on my part, can you recommend troubleshooting tips?

Thank you, Sincerely, Steve Jackson

### Additional contract requirements

- Add a public function `valid_pypi_name(package_spec: str) -> Optional[str]` in module `pipx.package_specifier`. It returns the canonicalized PyPI package name (lower-case, normalized) when the specifier has no associated URL, and returns `None` when a URL is present.
- Add a public function `fix_package_name(package_or_url: str, package: str) -> str` in module `pipx.package_specifier`. It returns a corrected package specifier in which the name component is forced to `package` while preserving any extras and URL that were originally present. If the original specifier cannot be parsed as a PEP 508 requirement, it is returned unchanged. For example, `fix_package_name("nox[extra]@https://github.com/ambv/black/archive/18.9b0.zip", "black")` returns exactly `black[extra]@ https://github.com/ambv/black/archive/18.9b0.zip`.
- Add a public function `parse_specifier_for_metadata(package_spec: str) -> str` in module `pipx.package_specifier`. It returns the package specifier with environment markers and version specifiers removed, preserving any extras and URL. For the input `my-project[cli] @ git+ssh://git@bitbucket.org/my-company/myproject.git ; python_version<"3.7"` it returns exactly `my-project[cli]@ git+ssh://git@bitbucket.org/my-company/myproject.git`.
- Add a public function `parse_specifier_for_install(package_spec: str, pip_args: List[str]) -> Tuple[str, List[str]]` in module `pipx.package_specifier`. It returns the package specifier suitable for installation together with the adjusted pip arguments, preserving any extras and URL present in a PEP 508 requirement so that the packages declared by the extra are installed.
