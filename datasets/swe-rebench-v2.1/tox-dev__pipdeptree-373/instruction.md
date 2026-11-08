Error in `canonicalize_name` with `None` metadata name
### What pipdeptree version are you using?

2.21.0

### Are you running pipdeptree in a virtual environment?

Yes

### Describe the problem

Install `docker-py` (https://github.com/docker/docker-py) and `pipdeptree`.
```shell
pip install docker pipdeptree
```

Then, try to display `docker` requirements:

```shell
pipdeptree  -p 'docker' --python 'auto'
Traceback (most recent call last):
  File "/home/francis/dev/miniconda/bin/pipdeptree", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/home/francis/dev/miniconda/lib/python3.11/site-packages/pipdeptree/__main__.py", line 31, in main
    pkgs = get_installed_distributions(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/francis/dev/miniconda/lib/python3.11/site-packages/pipdeptree/_discovery.py", line 58, in get_installed_distributions
    normalized_name = canonicalize_name(dist.metadata["Name"])
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/francis/dev/miniconda/lib/python3.11/site-packages/packaging/utils.py", line 47, in canonicalize_name
    value = _canonicalize_regex.sub("-", name).lower()
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: expected string or bytes-like object, got 'NoneType'
```

Although the package is installed and identified properly by `pip`:
```shell
pip show docker
Name: docker
Version: 6.1.3
Summary: A Python library for the Docker Engine API.
Home-page: https://github.com/docker/docker-py
Author:
Author-email:
License: Apache License 2.0
Location: /home/francis/dev/miniconda/envs/weaver-py310/lib/python3.10/site-packages
Requires: packaging, requests, urllib3, websocket-client
Required-by: weaver
```

### Additional contract requirements

- A distribution's metadata is considered missing or invalid when its `Name` value is absent or `None`.
- When a distribution has missing or invalid metadata, write a warning to stderr beginning with the exact line `Warning!!! Missing or invalid metadata found in the following site dirs:`. Include the affected site directory path on its own line, followed by a line of 72 hyphens.
- Distributions with missing or invalid metadata must not be included in the returned list of installed distributions.
- Distributions with valid metadata must still be included in the returned list even when other distributions in the same environment have missing or invalid metadata.
