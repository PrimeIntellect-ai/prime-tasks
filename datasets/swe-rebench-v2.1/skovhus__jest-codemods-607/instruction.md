support jasmine spyOnProperty
jasmine can spy on properties , [see their docs](https://jasmine.github.io/tutorials/spying_on_properties).

## Desired behaviour
Input:
```ts
spyOnProperty(component, 'propertyName1').and.returnValue(42);
spyOnProperty(component, 'propertyName2', 'get').and.returnValue(true);
```

should be transformed to:
```ts
jest.spyOn(component, 'propertyName1', 'get').mockReturnValue(42);
jest.spyOn(component, 'propertyName2', 'get').mockReturnValue(true);
```
