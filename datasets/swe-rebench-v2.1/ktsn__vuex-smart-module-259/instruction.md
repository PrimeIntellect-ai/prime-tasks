Jest TS: mocking mutations in actions fails
Hello,

I am writing some Jest tests for a store module written with `vuex-smart-modules@0.4.2`. I've encountered a problem when testing actions that call a mutation via the `this.mutations` property.

VSCode reports a `No overload matches this call.` error when trying to inject a `mutations` property in the `inject` function.

Here is an example code:

```ts
import { Mutations, Actions, Getters, inject } from 'vuex-smart-module';

class DemoState {
  str = 'hello';
}

class DemoMutations extends Mutations<DemoState> {
  update(str: string) {
    this.state.str = str;
  }
}

class DemoActions extends Actions<
  DemoState,
  Getters<DemoState>,
  DemoMutations,
  DemoActions
> {
  update(payload: string) {
    this.mutations.update(payload);
  }
}

test('action update', () => {
  const update = jest.fn();
  const actions = inject(DemoActions, { // <-- ERROR HERE
    state: new DemoState(),
    mutations: {
      update,
    },
  });

  actions.update('world');
  expect(update).toHaveBeenCalledWith('world');
});

```

The error seems to bother just the TS checker, because Jest tests do not fail.

Any hint on how to solve the issue?
