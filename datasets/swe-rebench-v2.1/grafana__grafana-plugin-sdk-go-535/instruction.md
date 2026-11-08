Supporting managed app plugins
**This is probably no a bug. Describing the situation below and re can re-categorize**

**What happened**:
Was working on a Grafana plugin that needed both a backend and frontend plugin, but was an **app plugin**. I tried to follow the managed backend approach, which allows me to access the `jsonData` and `secredJsonData` upon instance creation. For this, I followed examples like [this one](https://github.com/grafana/grafana-iot-twinmaker-app/blob/67a389a860205eea0d16e8b921d9fbae0878ea02/pkg/main.go#L12), even though I knew my plugin wasn't a datasource one.

Since this is not a `datasource` plugin, each `CallResourceRequest` incoming from the frontend will include `AppInstanceSettings` instead of `DatasourceInstanceSettings`. That means that generating the instance key will fail with [this](https://github.com/grafana/grafana-plugin-sdk-go/blob/3f3bfe95595cb3d4b3fafc7b9e4a36cd90f5ba69/backend/datasource/instance_provider.go#L45) error.

**What you expected to happen**:
Everything to work as expected.

**How to reproduce it (as minimally and precisely as possible)**:
Create an app plugin, and try to fit it inside the `datasource.Manage` approach.

**Anything else we need to know?**:

First tried to make the `datasource.InstanceProvider` consider the `AppInstanceSettings` as well, but the logic is more coupled for datasource stuff. Maybe the way to go is doing something like this.

https://github.com/grafana/grafana-plugin-sdk-go/compare/pablo/add-support-app-plugins?expand=1

**Environment**:
- SDK version:
- Grafana version:
- Go version:

### Additional contract requirements

- Managed app operations must accept a request context containing `AppInstanceSettings` without requiring datasource instance settings, and must be able to create the app instance for that context.
- App instance creation must make that context’s configured app settings available to the instance creator.
- The `backend/app` package offers the app counterpart of `datasource.NewInstanceManager`: `NewInstanceManager(factory)` takes a factory that receives `backend.AppInstanceSettings` and returns an `instancemgmt.Instance` (or an error), and returns an `instancemgmt.InstanceManager` whose `Get` accepts a `backend.PluginContext` carrying `AppInstanceSettings`.
