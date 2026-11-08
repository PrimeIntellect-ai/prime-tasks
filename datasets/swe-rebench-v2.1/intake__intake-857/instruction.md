Unbound local error when setting cache path with environment variables
Hi there,
I've been experiencing an error when providing intake with a local cache path using environment variables.
I'm using python 3.12.8 and intake 2.0.7

## Steps to reproduce

- set an environment variable (using bash on linux)

```bash
export INTAKE_CACHE="icache"
```
- start a python console and import intake

I would expect intake to store files in a folder called `icache` in the current working directory. However, I get this error:
>   File "/home/jroettenbacher/miniforge3/envs/update-requirements/lib/python3.12/site-packages/intake/config.py", line 162, in load_env
    self[k2] = val
               ^^^
UnboundLocalError: cannot access local variable 'val' where it is not associated with a value

As far as I can tell the problem arises as `ast.literal_eval()`, which loads the environment variables, does not like string input. Except it wants everything to be quoted even strings. So `'"icache"'` would work and would create a folder called `"icache"`, which I don't want. Linux can do that but Windows throws an error because of this.

[HIDDEN]

It's possible to work around this by not working with local environment variables but I think this should be something one can do. Or at least could do with version 1?

I'm open to work on this problem but would love some insight and guidance on where to start. Or if I'm using local environment variables the wrong way?

Best Johannes

### Additional contract requirements

- An unquoted environment variable value that is not a valid Python literal must be usable as its original string rather than causing configuration loading to fail.
- The `Config` configuration key `environment_conf_parse` must accept the value `warn`. When an environment variable value cannot be parsed, this setting must emit a `UserWarning` whose message contains `environment variable` and use the original value as a string.
