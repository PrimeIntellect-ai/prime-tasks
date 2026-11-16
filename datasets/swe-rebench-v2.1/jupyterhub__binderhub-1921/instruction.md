Trailing / in repo URL is not stripped
This was first reported by @JuKo007.

### Bug description

I believe that in the the old UI, BinderHub was stripping the leading / in the URL provided by the user. For example, if the user provides

```
https://github.com/gesiscss/Jupyter4NFDI_survey_results/
```

the UI would process as

```
https://github.com/gesiscss/Jupyter4NFDI_survey_results
```

### How to reproduce

1. Go to https://notebooks.gesis.org/ or https://2i2c.mybinder.org/
2. Fill "URL" with `https://github.com/gesiscss/Jupyter4NFDI_survey_results/`

#### Expected behaviour

Launch URL to be

```
https://2i2c.mybinder.org/v2/gh/gesiscss/Jupyter4NFDI_survey_results/HEAD
```

#### Actual behaviour

Launch URL is

```
https://2i2c.mybinder.org/v2/gh/gesiscss/Jupyter4NFDI_survey_results//HEAD
```

Notice the `//`. This is making BinderHub to not be able to resolve the reference.

![Image](https://github.com/user-attachments/assets/b62a3021-113c-44ee-8091-f5627f0af6e6)

### Additional contract requirements

The repository providers expose a public `display_config` mapping (served to the
frontend as `repoProviders`). For the GitHub (`gh`), GitLab (`gl`) and Gist (`gist`)
providers, the `detect.regex` entry must capture the repository specification in its
`repo` group with any trailing `/` removed.

The launch URL for a repository is
`https://2i2c.mybinder.org/v2/{provider_id}/{repo}/{ref}`, where `provider_id` is the
provider's public `id` (`gh` for GitHub, `gl` for GitLab, `gist` for Gist), `repo` is
the value captured by the provider's `detect.regex` `repo` group, and `ref` is the
provider's default ref (`HEAD`). Consequently, a repository URL or spec that ends in
`/` must produce the same launch URL as the same value without the trailing `/`. For
the GitHub example above, the launch URL must be

```
https://2i2c.mybinder.org/v2/gh/gesiscss/Jupyter4NFDI_survey_results/HEAD
```
