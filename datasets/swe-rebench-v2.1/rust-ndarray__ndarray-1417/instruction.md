`ndarray` iterators don't always work well with `impl Iterator`
When writing some iterator helper functions around the base `ndarray` iterators, I found a scenario where the borrow checker rejects what seems to be valid code. The scenario is generating an iterator over indices matching some criteria in an `Array` of references.

```rust
use ndarray::{iter::IndexedIter, Array1, Ix1};

/// This doesn't compile:
///
/// > hidden type for `impl Iterator<Item = usize> + 'a` captures lifetime that does not appear in bounds
/// > hidden type ... captures the lifetime `'s` as defined here
///
/// Various alternatives I tried which have the same issue:
/// - `.iter().enumerate()` instead of `.indexed_iter()`
/// - `.filter_map()` instead of `.filter().map()`
pub fn nd_iter_non_empty_indices_not_compiling<'s, 'a>(
    array: &'a Array1<&'s str>,
) -> impl Iterator<Item = usize> + 'a {
    array
        .indexed_iter()
        .filter(|(_index, elem)| !elem.is_empty())
        .map(|(index, _elem)| index)
}

/// Adding `'a: 's` makes the function compile, but now code using it doesn't
/// compile because the constraint `'a: 's` is impossible: the container can't
/// outlive the contained elements.
///
/// ```
/// use ndarray::array;
/// use broken_iter::*;
/// let arr = array!["", "abc", "", "123"];
/// assert_eq!(nd_iter_non_empty_indices_broken(&arr).collect::<Vec<_>>(), vec![1, 3]);
/// ```
pub fn nd_iter_non_empty_indices_broken<'s, 'a: 's>(
    array: &'a Array1<&'s str>,
) -> impl Iterator<Item = usize> + 'a {
    array
        .indexed_iter()
        .filter(|(_index, elem)| !elem.is_empty())
        .map(|(index, _elem)| index)
}
```

The original problem I had was with a 2D array with more complex types and filtering operation, but the error is the same.

## Similar functions which work fine

I thought it might have been a limitation of the Rust compiler, but the same operation with a normal Rust slice (or `Vec`) works fine:

```rust
pub fn slice_iter_non_empty_indices<'s, 'a>(
    array: &'a [&'s str],
    // All of these also work:
    // array: &'a Box<[&'s str]>,
    // array: &'a Vec<&'s str>,
    // array: &'a LinkedList<&'s str>,
    // array: &'a HashSet<&'s str>,
) -> impl Iterator<Item = usize> + 'a {
    array
        .iter()
        .enumerate()
        .filter(|(_index, elem)| !elem.is_empty())
        .map(|(index, _elem)| index)
}
```

It also works if the iterator returns references:

```rust
/// A similar function which returns the `&str` elements themselves works fine.
/// ```
/// use ndarray::array;
/// use broken_iter::*;
/// let arr = array!["", "abc", "", "123"];
/// assert_eq!(nd_iter_non_empty_strings(&arr).collect::<Vec<_>>(), vec!["abc", "123"]);
/// ```
pub fn nd_iter_non_empty_strings<'s, 'a>(
    array: &'a Array1<&'s str>,
) -> impl Iterator<Item = &'s str> + 'a {
    array.iter().filter(|elem| !elem.is_empty()).cloned()
}
```

## Workaround

I am able to work around the issue by creating a custom type for the iterator, but it seems like all the extra boilerplate shouldn't be necessary, especially since it isn't required when working with `Vec`:

```rust
/// It works fine if I use a custom struct to do the filter/map.
///
/// ```
/// use ndarray::array;
/// use broken_iter::*;
/// assert_eq!(nd_iter_non_empty_indices_custom(&array!["", "abc", "", "123"]).collect::<Vec<_>>(), vec![1, 3]);
/// ```
pub fn nd_iter_non_empty_indices_custom<'s, 'a>(
    array: &'a Array1<&'s str>,
) -> NonEmptyIndices<'a, 's> {
    NonEmptyIndices {
        indexed_iter: array.indexed_iter(),
    }
}

pub struct NonEmptyIndices<'a, 's> {
    indexed_iter: IndexedIter<'a, &'s str, Ix1>,
}

impl<'a, 's> Iterator for NonEmptyIndices<'a, 's> {
    type Item = usize;

    fn next(&mut self) -> Option<Self::Item> {
        // Manual loop for the filter/map operation
        loop {
            let (index, elem) = self.indexed_iter.next()?;
            if !elem.is_empty() {
                return Some(index);
            }
        }
    }
}
```

EDIT:

I found a much better work-around by specifying a more concrete return type. (Also changed it to `filter_map` to simplify the type).

```rust
pub fn nd_iter_non_empty_indices_better<'s, 'a>(
    array: &'a Array1<&'s str>,
) -> FilterMap<
    IndexedIter<'a, &'s str, Ix1>,
    impl FnMut((usize, &'a &'s str)) -> Option<usize>,
> {
    array.indexed_iter().filter_map(
        |(index, elem)| {
            if !elem.is_empty() {
                Some(index)
            } else {
                None
            }
        },
    )
}
```

This isn't terrible to work with, but it's still weird that all of the types in `std::collections` work fine with `impl Iterator<Item = usize> + 'a` but `ndarray` types need the explicit return type.
