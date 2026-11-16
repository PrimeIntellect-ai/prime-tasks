Raise error if empty model passed to discretise.process_model
Currently fails on `mass_matrix` step. Should raise an error straight away if model.rhs and model.algebraic are both empty dicts

### Additional contract requirements

When both the right-hand-side and algebraic equation collections are empty, discretisation must reject the model before reaching the mass-matrix stage, rather than exposing the downstream empty-array concatenation failure. No particular exception class or other message wording is required.
