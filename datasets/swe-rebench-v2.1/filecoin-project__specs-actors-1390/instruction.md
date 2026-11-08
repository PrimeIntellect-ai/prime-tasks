Clients who apply for additional DataCap need to use a new address every time
In the current implementation of spec-actors we require Clients to treat DataCap as a "one time" credit card - per address you can only receive DataCap once.

Practically, this introduces complexity for normal clients, who as a result need to manage which address of theres has DataCap, which addresses have already _had_ DataCap, and so on.

Especially for web3 apps (like Slate) where the end-user is in control of their keys (but enabling Slate to handle the deal making) - we run into a scenario where the web3 dev needs to manage swapping out addresses for DataCap allocation / deal making unnecessarily.
