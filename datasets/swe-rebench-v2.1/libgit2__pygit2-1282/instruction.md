Push options support within pygit2
I am trying to determine how to use git_push_options with a remote push. I'm unable to find any documentation, tests or working examples.

My goal is to implement something similar to git using the following: `git push --push-option somevar=someval`

What I have gleaned from the `remote.py`  context manager is that I probably need to pass libgit2 `custom_headers` parameter. But, I'm not sure if I'm missing something or just off base.

```

class CustomRemoteCallbacks(RemoteCallbacks):
    """Provide callback with push options."""

    def __init__(
        self,
        credentials: Optional[Credentials] = None,
        certificate: Optional[Certificate] = None,
        **kwargs: Any,
    ) -> None:
        """Initialize remote callback with custom headers."""
        super().__init__(credentials=credentials, certificate=certificate)
        self.custom_headers = [f"{k}={v}" for k, v in kwargs.items()]
```

### Additional contract requirements

- A remote push must let callers supply zero or more Git-style push-option strings through the `push_options` argument. Each supplied string must be sent to a supporting server as a push option and be available to its pre-receive and post-receive hooks.
