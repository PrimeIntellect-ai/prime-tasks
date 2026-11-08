`updateConfig()` should check if new config is the same as the old one
### Description
<!--- [mandatory] Describe the functionality that should be added to the engine-->

`updateConfig()` is an expensive operation. It rebuilds the whole engine so we should avoid doing it when not necessary. This method should check if the new config is the same as the old one.

### Links
<!--- [optional] Any links that are related  -->
https://github.com/handsontable/handsontable/pull/10326
https://github.com/handsontable/hyperformula/issues/1252
