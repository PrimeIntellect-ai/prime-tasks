Unit's .toNumeric() incorrect immediately after calculation with mixed units
When doing calculations with mixed units, such as multiplying feet and meters, .toNumeric() returns an incorrect value immediately after the calculation. Once .formatUnits() has been called on the result, .toNumeric() returns the correct value.

An example at http://jsbin.com/wusavigugi/edit?html,js,output shows that
```
    const a = math.unit(1, 'ft').multiply(math.unit(1, 'meter'))
    document.write(a.toNumeric() + '<br>');
    document.write(a.formatUnits() + '<br>');
    document.write(a.toNumeric() + '<br>');
```

outputs
```
1
meter^2
0.3048
```
