Update head and tail to work for all Foldable
Currently Head and Tail only work for `Array`, but it is possible to implement them for all `Foldable`.

### Additional contract requirements

- `S.head :: Foldable f => f a -> Maybe a` returns `Just` the first element of any Foldable structure, or `Nothing` if the structure is empty. Its displayed type is `head :: Foldable f => f a -> Maybe a`.
- `S.last :: Foldable f => f a -> Maybe a` returns `Just` the last element of any Foldable structure, or `Nothing` if the structure is empty. Its displayed type is `last :: Foldable f => f a -> Maybe a`.
- `S.tail :: (Applicative f, Foldable f, Monoid f) => f a -> Maybe (f a)` returns `Just` the structure without its first element, or `Nothing` if the structure is empty. Its displayed type is `tail :: (Applicative f, Foldable f, Monoid f) => f a -> Maybe (f a)`.
- `S.init :: (Applicative f, Foldable f, Monoid f) => f a -> Maybe (f a)` returns `Just` the structure without its last element, or `Nothing` if the structure is empty. Its displayed type is `init :: (Applicative f, Foldable f, Monoid f) => f a -> Maybe (f a)`.
- Each of these functions must work for any Foldable structure, not only `Array`.
