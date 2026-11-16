Change default components to constraint to be all components
Currently the default components to constrain in e.g. Dirichlet and PeriodicDirichlet is the first component. It becomes pretty annoying to always have to specify, since you more often than not prescribe them all. For scalar problems "all components" is already the default in a way, but for vector problems it is really strange to default to just the first one.

I suggest that we default to all components instead. One alternative would be to always require the components to be specified explicitly.
