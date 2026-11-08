`.output()` should "recurse" on any component nodes
Until it meets a depth that wasn't rendered.  I.E.

```jsx
const Second = () => <div>second</div>;
const First = () => <Second>first</Second>;
expect(deep(<First />).output()).toEqual(<div>second</div>);
expect(shallow(<First />).output()).toEqual(<Second>first</Second>);
```
