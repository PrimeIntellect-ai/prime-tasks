Function prototype set to undefined inconsistently too late
## Describe the bug

On Hermes we never reach (in whitelistIntrinsics)

https://github.com/endojs/endo/blob/b3a31b1559118dcfcd3811e9632c3f28fba99a3c/packages/ses/src/permits-intrinsics.js#L303-L304

but reach here first instead

https://github.com/endojs/endo/blob/b3a31b1559118dcfcd3811e9632c3f28fba99a3c/packages/ses/src/intrinsics.js#L87-L103

order of events and conditions

[HIDDEN]

## Steps to reproduce

- https://github.com/endojs/endo/pull/2334
  - `yarn build:hermes && yarn test:hermes`

## Expected behavior

[HIDDEN]

## Platform environment

- macOS Sequoia 15.0.1
- Node v20.12.2
- Hermes v0.12.0 (lockdown), v0.13.0 (harden)
- @endo/base64@1.0.8-10-gb3a31b155

## Additional context

- https://github.com/endojs/endo/pull/2563#discussion_r1807041929

Note: on [Static Hermes](https://speakerdeck.com/tmikov2023/hermes-better-performance-with-bytecode-translation-react-universe-2024?slide=9) this is a non-issue, since [both](https://github.com/endojs/endo/pull/2563#discussion_r1811111552) prototype bugs are fixed

## Screenshots

<img width="471" alt="lockdown prototype property not whitelisted" src="https://github.com/endojs/endo/assets/1881059/f20e91e5-69d5-4f06-abeb-991f50a2cbc0">

### Additional contract requirements

- Lockdown must tolerate a function intrinsic whose own `prototype` property cannot be deleted and is not permitted: retain the function and the property, leave the property’s value as `undefined`, and complete without throwing a prototype-permit TypeError.
