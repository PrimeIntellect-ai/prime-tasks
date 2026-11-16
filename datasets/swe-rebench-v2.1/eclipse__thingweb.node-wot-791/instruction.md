emitEvent() refers to undefined variable
see https://github.com/eclipse/thingweb.node-wot/blob/efc647961038cddbfb677b7573af680ae212514d/packages/core/src/exposed-thing.ts#L162

the 2nd branch points to `this.eventListener` which does not exist.

https://github.com/eclipse/thingweb.node-wot/blob/efc647961038cddbfb677b7573af680ae212514d/packages/core/src/exposed-thing.ts#L177-L186

[HIDDEN]
@relu91 do you know?

EDIT: To be honest I am not sure what the 2nd branch is for?

### Additional contract requirements

- Emitting an existing event must not fail because of undefined listener references and must deliver the supplied data to every subscriber registered for that event, including subscribers associated with different forms.
