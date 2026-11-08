Initialization versus runtime config
While setting up our dependency injection, I ran into some problems in the way some config options are being passed around.

Concretely, starting the server from the CLI allows you to pass a `port`. This `port` determines the `baseUrl`. This `baseUrl` is passed into the constructors of several components.
The problem here is that this makes it impossible to have a clean standalone dependency injection config to instantiate components, since we depend on values from the CLI, which are only available _after_ component instantiation.

If we would make a **cleaner separation** of **initialization config** (what goes in the config file), and **runtime config** (what is passed from the CLI), we should be able to solve this.

Concretely, what I would propose is to create a new **`RuntimeConfig`** component that can be passed to other components during dependency injection. While DI is going on, this component will not contain any data yet. When DI is done, and the server is started, it can be populated with data derived from the CLI, such as `port`, `baseUrl`, ... Other components can then read this data from `RuntimeConfig` at runtime.

The important thing to take into account here is that `RuntimeConfig` is passed around at initialization time, but can only be read at runtime.

Of course, we could still define default values in `RuntimeConfig` via our config file. This would mean that we could define a port in our config file, but if we pass one via the CLI, it would be overridden.

_For reference, LDF server does something similar with [`UrlData`](https://github.com/LinkedDataFragments/Server.js/blob/6cd5b59c6ba8a7dc1e7ecc7072d90bdfab492849/packages/core/lib/UrlData.js)_

Any thoughts before I implement this?

### Additional contract requirements

- Add a public class `RuntimeConfig` in module `src/init/RuntimeConfig`.
- `RuntimeConfig` has a constructor accepting an optional data object with optional fields `port` (number), `base` (string) and `rootFilepath` (string). When omitted, `port` defaults to `3000` and `base` defaults to `http://localhost:<port>/`.
- `RuntimeConfig` exposes a `reset(data)` method that accepts the same optional fields and updates the stored values accordingly.
- `RuntimeConfig` exposes getters `port` (number), `base` (string) and `rootFilepath` (string).
- Add a public type `RuntimeConfigData` in module `src/init/RuntimeConfig` describing an object with optional fields `port?: number`, `base?: string` and `rootFilepath?: string`.
- `SimpleResourceStore` is constructed with a `RuntimeConfig` instead of a base URL string.
- `FileResourceStore` is constructed with a `RuntimeConfig`, an `InteractionController` and a `MetadataController`.
- `UrlContainerManager` is constructed with a `RuntimeConfig`.
- `Setup` is constructed with an `ExpressHttpServer`, a `ResourceStore`, an `AclManager` and a `RuntimeConfig`; its `setup()` method takes no arguments and uses the port and base from the `RuntimeConfig`.
