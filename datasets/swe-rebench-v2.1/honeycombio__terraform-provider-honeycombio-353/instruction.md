data source: auth metadata
Build a new data source to query the data from the `/1/auth` endpoint and make it available to Terraform configurations (potential name `honeycombio_auth_metadata`?)

Would expose at minimum the team and environment names and slugs. Unclear if the key permissions are of interest?

### Additional contract requirements

The data source is named `honeycombio_auth_metadata` and takes no arguments.

It exposes the following attributes:

* `team.name` – the name of the Team the API key is scoped to.
* `team.slug` – the slug of the Team the API key is scoped to.
* `environment.classic` – `true` if the API key belongs to a Classic environment (i.e. the environment slug is empty), `false` otherwise.
* `environment.name` – the name of the Environment the API key is scoped to; null for Classic environments.
* `environment.slug` – the slug of the Environment the API key is scoped to; null for Classic environments.
* `api_key_access.boards` – whether the API key can create and manage Boards.
* `api_key_access.columns` – whether the API key can create and manage Queries, Columns, Derived Columns, and Query Annotations.
* `api_key_access.datasets` – whether the API key can create and manage Datasets.
* `api_key_access.events` – whether the API key can send events to Honeycomb.
* `api_key_access.markers` – whether the API key can create and manage Markers.
* `api_key_access.queries` – whether the API key can execute existing Queries via the Query Data API.
* `api_key_access.recipients` – whether the API key can create and manage Recipients.
* `api_key_access.slos` – whether the API key can create and manage SLOs.
* `api_key_access.triggers` – whether the API key can create and manage Triggers.
