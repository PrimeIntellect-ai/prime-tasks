Update TableHeader.Cell prop types to support type `number` for `colSpan`
## 🚀 Feature request

**Current Behavior**

* Using `react-table` passes a number to the `colSpan` prop
* This results in a console error due to invalid prop types

<img width="970" alt="Screen Shot 2021-05-28 at 9 02 21 AM" src="https://user-images.githubusercontent.com/3613392/119988101-c5872c00-bf93-11eb-8dfd-d479498f496e.png">

**Desired Behavior**

* `react-table` defaults should not cause prop type errors when used with Matchbox components

**Suggested Solution**

* `colSpan` for `TableHeader.Cell` should accept type of both `string` and `number`

**Who does this impact? Who is this for?**

* Only impacts FE engineers DX, not end users
