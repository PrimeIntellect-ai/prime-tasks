Add static code for supporting universe domain (to be used in both GAPICs and Apiary)
Universes other than the default `"googleapis.com"` need to be supported in both GAPICs and Apiary. The following code was added to GAPICs but can be moved to `python-api-core`:

```python3
def _get_universe_domain(
    client_universe_domain: Optional[str], universe_domain_env: Optional[str]
) -> str:  # temp disable Optional
    """Return the universe domain used by the client.

    Args:
        client_universe_domain (Optional[str]): The universe domain configured via the client options.
        universe_domain_env (Optional[str]): The universe domain configured via the "GOOGLE_CLOUD_UNIVERSE_DOMAIN" environment variable.

    Returns:
        str: The universe domain to be used by the client.

    Raises:
        ValueError: If the universe domain is an empty string.
    """
    [HIDDEN]


def _compare_universes(
    client_universe: str, credentials: Union[ga_credentials, oauth2_credentials]
) -> bool:
    """Returns True iff the universe domains used by the client and credentials match.

    Args:
        client_universe (str): The universe domain configured via the client options.
        credentials Union[google.auth.credentials.Credentials, oauth2client.client.Credentials]: The credentials being used in the client.

    Returns:
        bool: True iff client_universe matches the universe in credentials.

    Raises:
        ValueError: when client_universe does not match the universe in credentials.
    """
    [HIDDEN]

```

### Additional contract requirements

The universe-domain helpers are public in the module `google.api_core.universe`:

- `DEFAULT_UNIVERSE` is the string `"googleapis.com"`.
- `determine_domain(client_universe_domain: Optional[str], universe_domain_env: Optional[str]) -> str` returns the resolved universe domain, preferring `client_universe_domain`, then `universe_domain_env`, then `DEFAULT_UNIVERSE`, and raises `EmptyUniverseError` when the resolved domain is empty or consists only of whitespace.
- `compare_domains(client_universe: str, credentials: Any) -> bool` returns `True` when the client universe matches the universe domain found on the credentials (using `DEFAULT_UNIVERSE` when the credentials do not expose a `universe_domain`), and raises `UniverseMismatchError` when they differ.
- `EmptyUniverseError` and `UniverseMismatchError` are subclasses of `ValueError`.
- `UniverseMismatchError(client_universe: str, credentials_universe: str)` is publicly constructible from those two arguments; its message includes both universe domains and references the default universe.
