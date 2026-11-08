Can't access subModules actions or mutations of a SubModule from context(store).modules
Hey, thanks for your last release allowing subModules access with symbols!

But there is a bug, we can't access actions or mutations of submodules with the `context(store).modules.nameOfModule` feature.
The only way to access it, is, with the `option.modules!.nameOfModule.context(store)` way.

![subModulesInMountedHook](https://user-images.githubusercontent.com/37144206/85847825-6aa7ec00-b7a8-11ea-894b-8bd173f006ad.png)

Here are the log of this mounted hook:
![logOfSubModulesActions](https://user-images.githubusercontent.com/37144206/85847833-6c71af80-b7a8-11ea-9325-8b1ceccb7810.png)

As we can see the first way doesn't show anything when we try to show the actions of a submodules,  it's the same for `actions` and `mutations`. (getters and state are shown)

BTW: On the readme, there is only the first way specified.

### Additional contract requirements

- `Module`'s constructor options accept a `modules` field: a record mapping child-module names to `Module` instances.
- `Context.modules`, accessed as `module.context(store).modules`, maps each declared child-module name to a `Context` for that sub-module. Each sub-module context exposes the sub-module's `state`, `getters`, `actions`, and `mutations`, so that `ctx.modules.<name>.actions.<action>(payload)` and `ctx.modules.<name>.mutations.<mutation>(payload)` invoke the sub-module's action and mutation respectively.
