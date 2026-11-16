Change verifreg AllocationRequest to use ActorID
Instead of an address. This is for consistency with other APIs.

SPs and verified clients both must be actors that are instantiated on the network, so should have Actor IDs.
