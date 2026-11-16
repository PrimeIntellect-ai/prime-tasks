If location annotated with @Location is inside object/class - there will be error thrown: "Location annotation must be present to leverage notarized location api"
**Describe the bug**
Annotated location with `@Location` doesn't work inside of other object or classs.

**To Reproduce**
Steps to reproduce the behavior:
1. Open in your IDE: `LocationPlayground.kt` in `kompendium-playground` module
2. wrap TestLocations class inside some object
3. Execute main()
4. See error: "Location annotation must be present to leverage notarized location api"

**Expected behavior**
There should not be any errors, because annotation is present (looks like `LocationMethodParser` just doesn't expect such situation)

**Additional context**
Add any other context about the problem here.
