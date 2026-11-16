deprecate utils modules that are not intended for end-users
## Description of the problem
Most of our utils modules are not really intended to be used by end-users , but should be used via high-level interfaces that call these methods.

This follows an anti-pattern where there is high coupling between the `utils` module and other modules and reduced cohesion inside modules like `dataset`.

Also this crowds our online documentation with irrelevant functions no end-user will need.

## Description of a solution

Instead, we should increase the cohesion inside each module and reduce coupling between modules.

Candidates are:
- [x] `utils.aois` #1080
- [x] `utils.archives` -> `dataset._utils.archives` #1028
- [x] `utils.checks` -> `_utils._checks` #1094
- [x] remove `utils.decorators` #1008
- [x] `utils.downloads` -> `dataset._utils.downloads` #1030
- [x] `utils.filters` -> `events._utils._filters` #1032
- [x] `utils.parsing` -> `gaze._utils.parsing` #976
- [x] `utils.paths` -> `_utils._paths` #1029
- [ ] `utils.plotting` -> `plotting._utils.matlab` #1081
- [x] `utils.strings` -> `_utils._strings` #1031

### Additional contract requirements

String-pattern conversion is also available from `pymovements._utils._strings` with its existing conversion behavior. Calls through the former `pymovements.utils.strings` interface continue to work and notify callers with a `DeprecationWarning`. Dataset filename scanning and image-stimulus file discovery use the relocated functionality without emitting that deprecation warning during normal use.
