bug: Batch config schema is not appended to target's own config schema if the target supports the "batch" capability
### Singer SDK Version

0.30.0

### Is this a regression?

- [ ] Yes

### Python Version

NA

### Bug scope

Configuration (settings parsing, validation, etc.)

### Operating System

NA

### Description

Similar to what is done for taps:

https://github.com/meltano/sdk/blob/781bb049c4ec75916b908d424b42dd030f1a1780/singer_sdk/tap_base.py#L210-L211

but I don't think we should add to the default target capabilities and let each target handle that on their own (see https://github.com/MeltanoLabs/target-snowflake/issues/99):

https://github.com/meltano/sdk/blob/781bb049c4ec75916b908d424b42dd030f1a1780/singer_sdk/target_base.py#L92-L103

### Code

_No response_

### Additional contract requirements

- A target exposes its metadata through `Target._get_about_info()`, which returns an object with:
  - `capabilities`: the list of `PluginCapabilities` members the target advertises.
  - `settings`: the target's configuration JSON schema, including the built-in sections for the capabilities it advertises (for example `stream_maps`, `flattening`, and `batch_config`).
- When a target advertises the `PluginCapabilities.BATCH` capability, its configuration schema includes the `batch_config` setting. A target that does not advertise the `BATCH` capability does not include `batch_config`.
