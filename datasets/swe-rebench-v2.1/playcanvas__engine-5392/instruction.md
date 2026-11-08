`AnimComponent#reset` bad processing on parameters
AnimComponent#reset

https://github.com/playcanvas/engine/blob/256dd83c21750e8c84cd1eb4cafd9000c34f4573/src/framework/components/anim/component.js#L455

The reset method just copy references of parameter objects from origin stateGraph.parameters. If I reset an AnimComponent instance, then all changes, I made on the instance, will applied to the origin stateGraph.parameters. That makes the aseet dirty, and I cannot "reset" the AnimComponent instance anymore.

The reset method should works as how AnimComponent#loadStateGraph does.

https://github.com/playcanvas/engine/blob/256dd83c21750e8c84cd1eb4cafd9000c34f4573/src/framework/components/anim/component.js#L364

### Additional contract requirements

- `AnimComponent#reset()` must copy the state graph parameters the same way `AnimComponent#loadStateGraph()` does: each parameter must be copied into a new object, so that changing a parameter value on the component instance after `reset()` does not mutate the original state graph's parameters.
