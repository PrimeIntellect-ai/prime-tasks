Navlinks with state reference
Navlinks have an attribute `transitionTo` which is mapped at the moment to the `href` attribute or to the `to` attribute depending on the specific project flavor.

However, there's no transformation there for the content, so you have to specify the url as the attribute, ex: `/about-us`. It would be nice to be able to set only the state in which you wish to arrive (urls are just a meta info for each state value of the router).

So ideally, we should be able to set `about` as the attribute and the resolver will check the route stateDefinition and will extract the meta information (which url needs to go as a href/to for the navlink)

### Additional contract requirements

- Add a public function `resolveNavlinks(uidlNode: UIDLNode, routesDefinition: UIDLStateDefinition): void` in module `packages/teleport-generator-core/src/resolver/utils.ts`. It walks the UIDL element tree, finds elements of type `navlink`, and replaces the content of each such element's static `transitionTo` attribute with the `meta.path` of the route state value in `routesDefinition` that matches the attribute's current value.
- If a `navlink`'s `transitionTo` attribute is dynamic, `resolveNavlinks` throws an `Error` whose message includes `Navlink does not support dynamic 'transitionTo' attributes`.
- When the referenced state has no defined path, `resolveNavlinks` emits a `console.warn` with the message `No path was defined for router state: '${state}'.`, where `${state}` is the referenced state value.
- Normal UIDL resolution (`Resolver.resolveUIDL`) applies the same navlink resolution to a component's navlinks when the generator options contain `projectRouteDefinition`, set to the project's route state definition. Every navlink whose `transitionTo` value matches a state in that definition is resolved to that state's `meta.path`, regardless of which state it is.
