Panic when using extends without specifying service
A panic occurred on this line: https://github.com/compose-spec/compose-go/blob/ca961cc58145b2b1b8221f2a0c4e9734772156fc/loader/extends.go#L71C4-L71C30

When I used a config such as:
```yml
  my-service:
    extends:
      file: ../other-project/docker-compose.yml
      # I forgot to put this:
      # service: other-service-name

```

```
panic: interface conversion: interface {} is nil, not string

goroutine 1 [running]:
github.com/compose-spec/compose-go/v2/loader.applyServiceExtends({0x10497ebc8, 0x140005160c0}, {0x14000495600, 0x9}, 0x14000517560, 0x14000134e10, 0x14000596ba0, {0x140005968a8, 0x1, 0x1})
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/extends.go:71 +0x85c
github.com/compose-spec/compose-go/v2/loader.ApplyExtends({0x10497ebc8, 0x140005160c0}, 0x14000516840, 0x14000134e10, 0x14000596ba0, {0x140005968a8, 0x1, 0x1})
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/extends.go:40 +0x124
github.com/compose-spec/compose-go/v2/loader.loadYamlFile.func1({0x1044dbe00?, 0x14000516600?}, {0x140005968a8, 0x1, 0x1})
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:448 +0x12c
github.com/compose-spec/compose-go/v2/loader.loadYamlFile({0x10497ec00, 0x14000469630}, {{0x1400049f800, 0x35}, {0x140002c2000, 0x779, 0x77a}, 0x0}, 0x14000134e10, {0x1400049f800, ...}, ...)
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:515 +0x440
github.com/compose-spec/compose-go/v2/loader.loadYamlModel({0x10497ec00, 0x14000469630}, {{0x0, 0x0}, {0x1400049f800, 0x22}, {0x140001330b0, 0x1, 0x1}, 0x14000132db0}, ...)
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:376 +0x110
github.com/compose-spec/compose-go/v2/loader.load({0x10497ec00, 0x14000469630}, {{0x0, 0x0}, {0x1400049f800, 0x22}, {0x140001330b0, 0x1, 0x1}, 0x14000132db0}, ...)
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:536 +0x260
github.com/compose-spec/compose-go/v2/loader.loadModelWithContext({0x10497ec00, 0x14000469630}, 0x14000510000, 0x14000134e10)
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:348 +0xc4
github.com/compose-spec/compose-go/v2/loader.LoadWithContext({0x10497ec00, 0x14000469630}, {{0x0, 0x0}, {0x1400049f800, 0x22}, {0x140001330b0, 0x1, 0x1}, 0x14000132db0}, ...)
	github.com/compose-spec/compose-go/v2@v2.4.9/loader/loader.go:324 +0xc8
github.com/compose-spec/compose-go/v2/cli.(*ProjectOptions).LoadProject(0x14000134c60, {0x10497ec00, 0x14000469630})
	github.com/compose-spec/compose-go/v2@v2.4.9/cli/options.go:446 +0xa0
github.com/docker/compose/v2/cmd/compose.(*ProjectOptions).ToProject(0x14000807e00, {0x10497ec00, 0x14000469630}, {0x1049a7300, 0x14000429400}, {0x105f5ad60, 0x0, 0x0}, {0x14000597728, 0x2, ...})
	github.com/docker/compose/v2/cmd/compose/compose.go:336 +0x448
github.com/docker/compose/v2/cmd/compose.runBuild({0x10497ec00, 0x14000469630}, {0x1049a7300, 0x14000429400}, {0x1049aca28, 0x14000412940}, {0x14000807e00, 0x0, 0x0, 0x0, ...}, ...)
	github.com/docker/compose/v2/cmd/compose/build.go:139 +0xa4
github.com/docker/compose/v2/cmd/compose.buildCommand.func2({0x10497ec00, 0x14000469630}, 0x1400001e308, {0x105f5ad60, 0x0, 0x0})
	github.com/docker/compose/v2/cmd/compose/build.go:109 +0x164
github.com/docker/compose/v2/cmd/compose.buildCommand.AdaptCmd.func4(0x1400001e308, {0x105f5ad60, 0x0, 0x0})
	github.com/docker/compose/v2/cmd/compose/compose.go:122 +0x10c
github.com/docker/cli/cli-plugins/plugin.RunPlugin.func1.1.2(0x1400001e308, {0x105f5ad60, 0x0, 0x0})
	github.com/docker/cli@v28.0.1+incompatible/cli-plugins/plugin/plugin.go:65 +0x68
github.com/docker/compose/v2/cmd/cmdtrace.Setup.wrapRunE.func2(0x1400001e308?, {0x105f5ad60?, 0x0?, 0x0?})
	github.com/docker/compose/v2/cmd/cmdtrace/cmd_span.go:85 +0x58
github.com/spf13/cobra.(*Command).execute(0x1400001e308, {0x14000481550, 0x0, 0x0})
	github.com/spf13/cobra@v1.9.1/command.go:1015 +0x82c
github.com/spf13/cobra.(*Command).ExecuteC(0x1400002cf08)
	github.com/spf13/cobra@v1.9.1/command.go:1148 +0x350
github.com/spf13/cobra.(*Command).Execute(...)
	github.com/spf13/cobra@v1.9.1/command.go:1071
github.com/docker/cli/cli-plugins/plugin.RunPlugin(0x14000429400, 0x14000212f08, {{0x103e3e929, 0x5}, {0x103e4890c, 0xb}, {0x1041ff880, 0x11}, {0x0, 0x0}, ...})
	github.com/docker/cli@v28.0.1+incompatible/cli-plugins/plugin/plugin.go:80 +0x138
github.com/docker/cli/cli-plugins/plugin.Run(0x1049472d8, {{0x103e3e929, 0x5}, {0x103e4890c, 0xb}, {0x1041ff880, 0x11}, {0x0, 0x0}, {0x0, ...}})
	github.com/docker/cli@v28.0.1+incompatible/cli-plugins/plugin/plugin.go:95 +0x124
main.pluginMain()
	github.com/docker/compose/v2/cmd/main.go:38 +0x98
main.main()
	github.com/docker/compose/v2/cmd/main.go:98 +0x1a4
```

### Additional contract requirements

When a service's `extends` is a mapping that omits the `service` key, loading the
project must not panic. Instead, loading must fail and return an error whose message
is exactly `extends.<service-name>.service is required`, where `<service-name>` is the
name of the service that declares the `extends` mapping (for example, for a service
named `test`, the message is `extends.test.service is required`).
