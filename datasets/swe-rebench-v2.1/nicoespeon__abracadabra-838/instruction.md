"Change Signature" doesn't work on a nested function
## Describe the bug

When I try to run "Change Signature" on a function nested inside another function, it doesn't really work.

At first I thought it wasn't doing anything, but after I wrote a test for it, I realized it might actually be changing the call sites but not the function itself?

(I'm uncertain because the unit tests aren't run using the actual vscode editor, which I understand is partly because Jest didn't seem to provide the APIs you'd need to write a runner analogous to the simple Mocha runner that the VSCode extension docs and examples suggest you use; it looks like Jest has a lot more layers than Mocha? I wonder if <https://github.com/macabeus/jest-environment-vscode-extension> would work for you?)

Actually, when I run it live it modifies the head of the outer function ...

## How to reproduce
I've actually written a test for this:

https://github.com/nicoespeon/abracadabra/blob/0def578c5dd37db9c9bc113507606d49138e5111/src/refactorings/change-signature/change-signature.test.ts#L176-L190

I've also submitted that as <https://github.com/nicoespeon/abracadabra/pull/838> (currently marked draft because I had no issue to reference and I'm not sure you want to merge a failing test), and you can see the failure there.

## Expected behavior

I expected changing the signature of a nested function to adjust both the parameters in the function itself, and the arguments passed in calls to the function; at worst, I expected the refactoring to be unavailable.

## Screenshots

_If applicable, add screenshots to help explain your problem._

## Additional information

- Version of the extension impacted: v7.0.0

_🧙‍ Add any other context about the problem here._
