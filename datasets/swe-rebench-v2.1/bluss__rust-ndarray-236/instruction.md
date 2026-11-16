Replace ArrayBase::assign_scalar with ArrayBase::fill
Is the shorter name worth it? The longer name has some consistency (but not much).

cc @SuperFluffy  I heard you wanted to change .assign_scalar. My suggestion is to just deprecate it (without changing it), and adding .fill() instead, that has the signature that you wanted.

### Additional contract requirements

Add `ArrayBase::fill` as a mutable-array operation that accepts its scalar value by value and replaces every element with a clone of that value. Keep `ArrayBase::assign_scalar` available with its existing `&A` argument and behavior, and mark it deprecated in favor of `fill`.
