[AttributedText][Bug] - Wrong placeholder map order breaks constructor
It looks like our `AttributedText` constructor is order-dependent on the entries in the placeholder map. This is undocumented and unintentional. Make the constructor order agnostic.
