Remove `variants` and related methods from `Actionlike`
              There are still quite a bit of `A::variants()` usage left. I'm kinda surprised that it has not broken anything else like it did. Is it within the scope of this pr to remove usage of `A::variants()` as you mentioned on Discord? The removal of `A::variants()` will not be trivial, I think. For `InputMap` it can use `iter()`, but `ActionState` doesn't have access to the map so it will require some thought.

_Originally posted by @100-TomatoJuice in https://github.com/Leafwing-Studios/leafwing-input-manager/issues/400#issuecomment-1806846091_
