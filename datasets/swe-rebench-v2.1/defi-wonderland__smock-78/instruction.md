Create fakes with Contract Interface
**Is your feature request related to a problem? Please describe.**
I often would like to test contracts that depend on external/3rd party contracts. I'd like to only import the interfaces for those contracts into my repo/codebase since they often times are implemented with a different solidity version than the one i'm using. Therefore in my project i'll have my contracts (their sourcecode) and interfaces for external contracts I use.

I try to create "fake" implementations of those external contracts using smock but am unable to, I need to source code for them.

**Describe the solution you'd like**
Being able to use `smock.fake()` with a contract interface.

**Describe alternatives you've considered**
I can stub out functionality for those contract interfaces, just have empty functions that do nothing and then use `smock.fake` but that's a hassle.

**Additional context**
I've tried using code like:
```
// IBasicController is an interface
await smock.fake("IBasicController");
```
and i get the error:
```
NomicLabsHardhatPluginError: You are trying to create a contract factory for the contract IBasicController, which is abstract and can't be deployed.
If you want to call a contract using IBasicController as its interface use the "getContractAt" function instead.
```
