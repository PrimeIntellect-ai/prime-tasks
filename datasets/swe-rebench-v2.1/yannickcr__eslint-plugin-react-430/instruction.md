prop-types doesn't complain about destructured props in stateless functions
The following should cause an error for missing proptype validations, but it doesn't.
```
const Test = ({ name }) => {
  return (
    <div>{name}</div>
  );
};
```

If you replace the destructuring with using the props object, it works as expected.
