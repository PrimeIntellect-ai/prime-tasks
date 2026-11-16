Set defaults for num_tokens and make it configurable
Even though we use the stock defaults for `num_tokens` we need to explicitly set it because the config builder uses a default of `num_tokens: 1`. It should be configurable as well in case users want to use a non-default value.



┆Issue is synchronized with this [Jira Task](https://k8ssandra.atlassian.net/browse/K8SSAND-923) by [Unito](https://www.unito.io)
┆Reviewer: 557058:376e6d8d-84b1-46a1-a227-0887055aa65a
┆Fix Versions: k8ssandra-operator-1.0.0-alpha.1
┆Issue Number: K8SSAND-923
┆Priority: Medium
