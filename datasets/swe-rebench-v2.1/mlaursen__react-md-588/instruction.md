[Slider] step behavior wrong in cases where min not zero
### Description
When using a slider with a step defined the increments are miscalculated and do not match the value provided by step.
### Images/Screenshots
![Image of Slider Error](https://i.imgur.com/H0wNuK6.png)
The incorrect bottom slider cannot be set to 2.5 or 2.75, despite those being evenly divisible by the 0.25 step starting at 0.5.
### Link to a gist or code sample where the issue can be reproduced
Issue is displayed on the forked codepen template:
[https://codepen.io/strickc/pen/VMdOLX](https://codepen.io/strickc/pen/VMdOLX)
<!--
You can save me even more time and help debugging process by using this codepen template:
https://codepen.io/mlaursen03/pen/ZLMWwX
-->
### Version
- React - 15
- React-MD - 1.2
- Browser - Chrome v61

I'd be interested in providing a fix for this bug if a pull request is welcome.

**Edited** to correct my confusion between the step and discreteTicks properties.

### Additional contract requirements

- When `normalized` is true, the returned distance must correspond to the nearest-step value; if the pointer is `pxOffset` pixels below that value's position, the distance must be `(pageX + pxOffset - left) / width * 100`.
- When `normalized` is false, the returned distance must be `(pageX - left) / width * 100`.
