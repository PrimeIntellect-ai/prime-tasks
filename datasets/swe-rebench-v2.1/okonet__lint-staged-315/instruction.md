Upgrade cosmiconfig to 3.x
https://github.com/davidtheclark/cosmiconfig 2.x offers caching and [`transform`](https://github.com/davidtheclark/cosmiconfig#transform) function that should potentially make #262 obsolete.

### Additional contract requirements

- Use cosmiconfig 3.x’s explorer `load` method to retrieve configuration, while preserving the existing configuration-loading behavior.
