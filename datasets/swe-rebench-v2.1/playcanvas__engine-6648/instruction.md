Allow entity components enabling order on hierarchy change
When working with custom components (e.g. added via code), we need some components to be enabled before others. At the moment the components are called in random order:

https://github.com/playcanvas/engine/blob/55a3ff8845f0cf30829aeec515f24ac98b6baf4d/src/framework/entity.js#L503-L520

For example, a body component and a constraint component for physics. The constraint component needs a body to be attached to. If the body component is enabled later, it will be added to the physics after the constraint, which will fail creating the constraint as it will fail to locate the body.

There is no elegant way of doing it today. We have to introduce a component dependency into another component that actually doesn't need to be aware if other components and their state. We also have to add some sort of systems to queue up the creation commands to wait for the other component to be enabled, which is pretty brittle.

### Additional contract requirements

- Components can declare a static `order` property (a number, default `0`). When an entity with multiple components changes hierarchy state, its components are enabled and disabled in ascending order of `order` (the lowest number first).
- When an entity has both `collision` and `rigidbody` components, invoke the `rigidbody` component's `onDisable` before the `collision` component's `onDisable`, and invoke the `rigidbody` component's `onEnable` before the `collision` component's `onEnable` when hierarchy state changes.
