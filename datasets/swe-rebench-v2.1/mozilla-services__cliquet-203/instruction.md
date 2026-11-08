Provide extra default settings in initialize_cliquet
In order to extend and override cliquet default settings in applications.

### Additional contract requirements

`initialize` accepts an optional mapping through the `default_settings` argument. Its entries supply defaults that may override Cliquet's built-in values or add application-specific settings. These settings are available during initialization, so they can affect initialization behavior that reads them.
