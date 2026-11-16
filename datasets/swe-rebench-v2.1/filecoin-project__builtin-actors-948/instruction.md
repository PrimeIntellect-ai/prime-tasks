Replace fetching control addresses with IsControllingAddress
A few other actors fetch the control addresses from the miner, then perform the ritual of resolving and comparing an address against them. Replace them with calls to the new `IsControllingAddress` method. Remove the existing accessor if possible.
