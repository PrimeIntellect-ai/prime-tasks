Allow ephemeral models to lazy load in runtime
## Is your feature request related to a problem? Please describe.

The current implementation of lazy loading in `caikit.runtime.model_management.model_manager` is centered around `local_models_dir`. This makes sense for physical models, but with the presence of the `ModelFinder` abstraction, we also want to support "auto-finders" that are able to infer a model's configuration without needing the model on disk physically.

An "auto-finder" may be configured to receive the `model_path` and find a model based on it in any arbitrary way. Given this, an auto-finder is free to play tricks with the on-disk path such as `os.path.basename` to strip off path prefixes, but this also interferes with the lazy-load sync's unloading logic which assumes that a model whose path begins with `local_models_dir` which is not present on disk has been deleted and therefore should be unloaded.

## Describe the solution you'd like

To solve this, we want the runtime `ModelManager` to explicitly permit lazy loading of non-disk models [HIDDEN].

## Describe alternatives you've considered

We could solve this by requiring auto-finders to be smart enough to handle this themselves, but this places several limitations on what finders can do and decentralizes the logic for this kind of ephemeral model.

## Additional context

This is currently limiting the use of `TGISAutoFinder` ([here](https://github.com/caikit/caikit-nlp/blob/main/caikit_nlp/model_management/tgis_auto_finder.py)) with `runtime`

### Additional contract requirements

- When `os.path.join(local_models_dir, model_id)` does not exist, the lazy-load path must use `model_id` as `model_path`, allowing a configured auto-finder to resolve and lazy-load the model. Local-model synchronization must not unload that model solely because the directory is absent.
