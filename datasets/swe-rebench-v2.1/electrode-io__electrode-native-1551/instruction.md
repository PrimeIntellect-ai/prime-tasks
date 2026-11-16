ern run-ios not able to identify ipad simulators
basically we are using same miniapp which we built it for android to generate the code for IOS and install it on IPAD. our target machine to run app in IPAD devices so when i run ern run-ios it compiles and generate the code required for IOS but ern is listing only mobile iphones and not able to identify IPad simulators. could you please share is there any fix we need to do it.

workaround: once ern-ios compiles the code we are terminating the process and run this command ->npx react-native run-ios --simulator="iPad (7th generation)" to install it on the ipad simulators

### Additional contract requirements

- `ern run-ios` must include iPad simulators, not only iPhone simulators, among the simulators it offers for selection.
- The public function `askUserToSelectAniPhoneSimulator()` in `ern-core/src/ios.ts` returns a `Promise` resolving to the selected simulator object, which contains at least `name`, `udid` and `version`.
- `askUserToSelectAniPhoneSimulator()` updates the stored iOS device configuration with the selected simulator's `udid`.
- When the user is prompted to choose a simulator, the prompt response uses the property name `selectedSimulator` for the chosen simulator.
