Running tox in --notest mode always succeeds
So the problem is that I run `tox --notest` in the `install` step in Travis CI and just `tox` in `script`.

Now, because there's a deps conflict it traced back and tox printed out an error. But the return code was `0` so travis just folded all output from `tox --notest` and it looked weirdly broken on the test stage. While the real reason is that it produced a pre-baked venv without crashing the whole thing in the right moment.

Current workaround is to manually parse the output:
https://github.com/ansible/molecule/blob/5f6bcc9/.travis.yml#L338-L341
