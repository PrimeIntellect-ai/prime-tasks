"Impacted"/downstream module wrongly receives *ForUpstreamModules properties in certain cases
Given `buildUpstream=true|always|derived` (and `mvn -am` in  case of `derived`) and one of the following two module setups:
- `A <- B* <- C <- D*` with `buildUpstreamMode=changed`
- `A <- B* <- C <- D` with `buildUpstreamMode=impacted`

(`*` marking a changed module)

results in `C` being subject to `skipTestsForUpstreamModules` and `argsForUpstreamModules` (if set), which is clearly wrong since `C` is "impacted" by the change to `B` and must therefore run all tests etc.
