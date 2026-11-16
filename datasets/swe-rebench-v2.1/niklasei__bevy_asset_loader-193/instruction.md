Nasty bug: Trying to load the same collection twice causes a freeze and no errors reported
Nasty bug: Trying to load the same collection twice causes a freeze and no errors reported
Version: 0.19

For example, do this in the foxtrot example:
...


 .add_loading_state(
            LoadingState::new(AppState::Loading)
                .continue_to_state(AppState::PostLoading)
                .load_collection:: < AudioAssets >()
                  .load_collection:: < AudioAssets >()  //this is duplicated and this causes the problem
              ....



      Suggestion:  Make this error case throw an error

### Additional contract requirements

- Registering the same asset collection more than once for a loading state must emit a warning (a log message at warning level) and must not prevent the loading state from completing. This applies both when the duplicate is registered through `LoadingState::load_collection` and when it is registered through `LoadingStateConfig::load_collection`.
