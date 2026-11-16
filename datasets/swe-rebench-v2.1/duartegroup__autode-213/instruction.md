Throw useful exception if `ade.Config.ts_template_folder_path = ""`

### Additional contract requirements

`get_ts_template_folder_path(folder_path)` in `autode.transition_states.templates`:

- When `Config.ts_template_folder_path` is set to a non-empty string, returns that
  configured path.
- When `Config.ts_template_folder_path` is `None`, returns the default TS template
  directory, which is the `lib` folder inside `autode/transition_states`.
