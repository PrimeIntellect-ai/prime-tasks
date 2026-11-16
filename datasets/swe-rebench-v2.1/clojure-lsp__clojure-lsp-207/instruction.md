Add initialization options to disable formatting providers
Calva provides its own formatter that is a customized version of cljfmt. I think the plan is to eventually merge any changes we need into main cljfmt and use it from clojure-lsp, but for now having lsp provide formatting can cause some confusion (VS Code allows a user to choose which formatter to use, but since it sees them as both coming from Calva, they are named the same in the UI picker).

Until we can use cljfmt from lsp, being able to disable formatters from lsp is desirable.

### Additional contract requirements

- The initialization options accept the keys `:document-formatting?` and `:document-range-formatting?`.
- The public function `client-settings` in namespace `clojure-lsp.main` takes an `InitializeParams` and returns a map of effective client settings that always contains `:document-formatting?` and `:document-range-formatting?`, each defaulting to `true` when not supplied.
- The server advertises the document formatting and document range formatting capabilities according to these settings: when a setting is `false`, the corresponding capability is not advertised.
