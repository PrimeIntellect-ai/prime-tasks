Cycle detection doesn't work well with fibers
[Cycle detection](https://github.com/Seldaek/monolog/blob/e68c00670e310e276da9624d75965f5d2f28aa80/src/Monolog/Logger.php#L324) is broken when using fibers, because it assumes that if the function is entered multiple times, it's a cycle. With fibers, the function might be entered multiple times in different fibers if one of them suspends somewhere within the function.

What are your thoughts to moving cycle detection to an interface? There could be a `NullCycleDetector` that doesn't detect cycles at all, a `CountingCycleDetector` and then [HIDDEN]. I'm of course also fine with fibers being supported natively, but I don't think it's a good idea to put this logic into `Logger` itself in that case.

### Additional contract requirements

- Logging in distinct fibers must not be classified as recursive merely because one fiber suspends while logging is active; genuine recursive logging must still be detected.
