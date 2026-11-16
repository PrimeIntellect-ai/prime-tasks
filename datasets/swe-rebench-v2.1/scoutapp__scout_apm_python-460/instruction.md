Instrument hug
Hug was reported used by 1% of developers in the [Python developers survey 2018](https://www.jetbrains.com/research/python-developers-survey-2018/). We should support it.

### Additional contract requirements

Set up Scout monitoring for a Hug application with the public API `scout_apm.hug.integrate_scout(hug_module_name, config)`. `hug_module_name` is the name of the module containing the Hug API definitions, and `config` is the Scout configuration to use. When monitoring is enabled, Scout records incoming Hug HTTP requests and their paths.
