animationName with array value not supported by babel-plugin
In an array with multiple animations is given as the value of the `animationName` attribute within a `makeStyles` call and the babel plugin optimizations are enabled, there is an error thrown at during build at the `babel:postprocess` stage indicating that `ruleValue.indexOf is not a function`:

![image](https://user-images.githubusercontent.com/7798177/203412603-9d5f11ff-9a8b-4b37-ab17-94a3b576bb93.png)

<img width="689" alt="image" src="https://user-images.githubusercontent.com/7798177/203412917-2bcfdc20-01b5-4287-b1d2-48d4a8fe54d6.png">

### Additional contract requirements

- When transforming an `animationName` array, preserve styling from each animation in the array.
