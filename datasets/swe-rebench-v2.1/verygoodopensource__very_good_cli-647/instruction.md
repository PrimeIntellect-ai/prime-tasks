fix: `--min-coverage` does not work when running with `--recursive`
**Description**

Currently if you run `very_good test --min-coverage 100 --recursive` it will go through each package it finds and run the tests. But if any of those packages don't have 100% test coverage there won't be an error displaying that.

Here I am running the command at the root of my project:
![image](https://user-images.githubusercontent.com/15887627/167681205-221aa8a0-1d05-44a3-99c7-d8fa6b9908d6.png)

It finds three packages, which is correct, but all three of them don't have 100% test coverage:
- `umbra_flutter`: ![image](https://user-images.githubusercontent.com/15887627/167681340-5fe86332-8c71-4150-a766-5ac2e4905688.png)
- `umbra_core`: ![image](https://user-images.githubusercontent.com/15887627/167681422-7a7d4eb3-e86e-4af9-83f2-0a6c9ac010eb.png)
- `umbra_cli`: ![image](https://user-images.githubusercontent.com/15887627/167681473-c83ed236-e26e-4617-a827-c2c5e49fbe84.png)

**Steps To Reproduce**

1. Create a repo with two packages, and ensure they don't have full test coverage
2. Run `very_good test --min-coverage 100 --recursive` at the root
3. Tests will succeed but no coverage is reported.

**Expected Behavior**
I expected that I was able to combine these flags together to run all my tests at the highest level and confirm that they all have the coverage I expected.

Related: https://github.com/VeryGoodOpenSource/very_good_cli/issues/383

### Additional contract requirements

When a recursive test run uses a minimum-coverage threshold, coverage must be checked for each package. If any package is below the threshold, the overall run must report failure.
