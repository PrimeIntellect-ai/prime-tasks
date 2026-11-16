support github enterprise server (GHE) in CI
## Description

It looks like `hvcs_domain` configuration seems to almost solve this but the same value is being used for the api and domain urls which is a problem.

https://github.com/relekang/python-semantic-release/blob/83798b7bf94569014e00a5f030ac46a5d4992fff/semantic_release/hvcs.py#L97-L104

https://github.com/relekang/python-semantic-release/blob/83798b7bf94569014e00a5f030ac46a5d4992fff/semantic_release/hvcs.py#L107-L116

Instead, it would be better to have a separate config value for api domain to use with custom domains.

Also, to provide built-in support for Github CI and Github enterprise server CI, it would be best to get these values from environment variables (without having to set `hvcs_domain` for enterprise CIs).

GITHUB_SERVER_URL | Returns the URL of the GitHub server. For example: https://github.com.
-- | --
GITHUB_API_URL | Returns the API URL. For example: https://api.github.com.

[Github CI Docs ref](https://docs.github.com/en/actions/reference/environment-variables#default-environment-variables)


## Use cases

- Can be used in GHE CI and GH CI

## Possible implementation

- To support custom domains, a new configuration variable called `hvcs_api_domain` can be used and then the `api_url` function can be changed to:

```python
class Github(Base):
    # rest of the code

    @staticmethod
    def api_url() -> str:
        """Github api_url property
        :return: The Github API URL
        """
        # not necessarily prefixed with api in the case of a custom domain, so
        # can't just default DEFAULT_DOMAIN to github.com
        [HIDDEN]

    # rest of the code
```

- To support Github and GHE CI, the `domain` and `api_url` methods in Github class can be modified as:

```python
class Github(Base):
    """Github helper class"""

    DEFAULT_DOMAIN = "github.com"
    _fix_mime_types()

    @staticmethod
    def domain() -> str:
        """Github domain property
        :return: The Github domain
        """
        [HIDDEN]

    @staticmethod
    def api_url() -> str:
        """Github api_url property
        :return: The Github API URL
        """
        # not necessarily prefixed with api in the case of a custom domain, so
        # can't just default DEFAULT_DOMAIN to github.com
        [HIDDEN]

    ... # rest of the code
```

### Additional contract requirements

- Configure the GitHub server domain and API domain independently with `hvcs_domain` and `hvcs_api_domain`, respectively. An explicit configuration value takes precedence over its corresponding environment variable.
- When `hvcs_domain` is unset, use `GITHUB_SERVER_URL`; the GitHub domain value must not include a URL scheme.
- When `hvcs_api_domain` is unset, use `GITHUB_API_URL`; the API URL must be a full HTTPS URL, with the scheme normalized as needed.
- If neither the corresponding configuration value nor environment variable is provided, retain the standard GitHub defaults.
