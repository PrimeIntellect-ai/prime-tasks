feat: allow target `MAX_SIZE_DEFAULT` to be externally configurable
In the base sink class we define a `MAX_SIZE_DEFAULT` thats set to 10,000 https://github.com/meltano/sdk/blob/e9f2c179fb3a8bcd103546209b4d1c4b8df78ec6/singer_sdk/sinks/core.py#L133. Thats a fine base default and target developers can override it if their target prefers smaller or larger batches.

The thing thats not supported today is the use case where I want to configure a target, say target-postgres, to output more frequently because my tap records are slow/expensive to get so the possibility of waiting until 10k records are retrieved, the batch is old enough to drain, or the sync completes, is undesirable. I might want to drain after every 50 records or so in some case.

One example that came up a while ago is from the map-gpt-embeddings plugin that requests from openai's api. It takes a while to embed all input data and each request costs money so preferably I'd drain as frequently as possible.

cc @edgarrmondragon

### Additional contract requirements

- Targets accept a `batch_size_rows` setting in their configuration that sets the maximum number of rows loaded in each record batch.
- `Sink.batch_size_rows` is a public property that returns the configured maximum number of rows per batch as an `int`, or `None` when the setting is not configured.
- `Sink.max_size` is a public property that returns the configured `batch_size_rows` when it is set, and otherwise returns the class default `MAX_SIZE_DEFAULT`.
