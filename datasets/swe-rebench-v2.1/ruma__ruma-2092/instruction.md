Allow to use `EventContent` for a type that is both global account data and room account data
Some MSCs declare that account data can have a global setting and be overriden per-room in the room account data (see #2065 for example). Currently the only way to do that is to declare two different types with `EventContent`, or probably declare a single type and implement the missing traits manually.

It would be nice to be able to declare both account data types with `EventContent`.

I am not sure of the ideal syntax:

1. A tuple: `kind = (GlobalAccountData, RoomAccountData)`,
2. Separated by `|` like `match` arms: `kind = GlobalAccountData | RoomAccountData`,
3. Since it's only possible for account data, use a new kind: `kind = GlobalAndRoomAccountData`.
