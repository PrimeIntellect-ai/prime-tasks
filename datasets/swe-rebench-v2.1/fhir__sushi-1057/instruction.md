SUSHI should warn on unused configuration properties in FSHOnly mode
When `sushi-config.yaml` is set to `FSHOnly: true`, many of the config properties are ignored (since SUSHI will not create an ImplementationGuide JSON file).  So... if an author does set these properties in `sushi-config.yaml`, it's very likely a mistake.

We should determine what properties are used in FSHOnly mode and what properties are extraneous -- and warn on the use of any extraneous ones when `FSHOnly` is `true`.
