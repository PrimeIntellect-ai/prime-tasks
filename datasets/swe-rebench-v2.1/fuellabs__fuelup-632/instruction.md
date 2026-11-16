fuelup default <name>
### Problem you are trying to solve

When choosing a name that does not exist either prompt the user to use the `fuelup show` command to check the toolchains or preferably automatically show the installed toolchains below.

![image](https://github.com/FuelLabs/fuelup/assets/36463/1e523140-acf5-42bc-b4c6-25d32011d245)
![image](https://github.com/FuelLabs/fuelup/assets/36463/509fc682-c5f1-4114-9974-5ff136953fa7)
Capitalize the `d` in `default`

![image](https://github.com/FuelLabs/fuelup/assets/36463/d1764bf2-3785-4616-9c90-521bd206f8ad)


### Solution you'd like

When choosing a name that does not exist either prompt the user to use the `fuelup show` command to check the toolchains or preferably automatically show the installed toolchains below.

### Notes

_No response_

### Additional contract requirements

- When the requested toolchain does not exist, write to stdout: `Toolchain with name '<resolved-name>' does not exist\n\n\u{1b}[1mInstalled toolchains\u{1b}[0m\n--------------------\n`, followed by each installed toolchain on its own line in the displayed order and a final blank line.
- In `fuelup show` output, the installed-toolchains heading must be `Installed toolchains`.
- On success, `fuelup default <name>` writes `Default toolchain set to '<resolved-name>'\n` to stdout.
- `fuelup toolchain new <name>` writes `New toolchain initialized: <name>\nDefault toolchain set to '<name>'\n` to stdout.
