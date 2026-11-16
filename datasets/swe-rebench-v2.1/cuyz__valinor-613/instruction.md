No MappingError anymore on invalid input (since v1.14.3)
Copied from [here](https://github.com/eliashaeussler/version-bumper/pull/32#issuecomment-2672549009):

> In both [failing test cases](https://github.com/eliashaeussler/version-bumper/actions/runs/13378833447/job/37363580385?pr=32), I map an [invalid file](https://github.com/eliashaeussler/version-bumper/blob/c8ed7f87855b3f913d072ac46f2539000abde9b2/tests/src/Fixtures/ConfigFiles/invalid-config.json) to a [value object](https://github.com/eliashaeussler/version-bumper/blob/0b0c1b04d1397a3bd6684208d13942359246b418/src/Config/VersionBumperConfig.php) which should throw a `MappingError`. This worked fine until valinor 1.14.2. Starting with v1.14.3, no error is thrown anymore.

Thanks again for all your efforts! ❤

### Additional contract requirements

- The invalid-input behaviour above applies to any iterable source, not only to a plain PHP array: when the source is an iterable (for example a `CuyZ\Valinor\Mapper\Source\Source` created from an iterable), superfluous keys must still cause a `MappingError`.
- Add a public method `transformIteratorToArray(): self` on `CuyZ\Valinor\Mapper\Tree\Shell` that returns a shell whose value is the plain PHP array obtained from an iterable value, and returns a new instance when a conversion occurs.
