Breakpoints bug when using numbers of different length
Hello hello,
I've encountered a weird behavior when dealing with breakpoints as objects. Regarding your documentation I came up with the following breakpoints within a breakpoints.js file:

```
const breakpoints = [
  '21em', // 336px
  '35em', // 560px
  '45em', // 720px
  '64em', // 1024px
  '75em', // 1200px
  '90em', // 1400px
  '100em', // 1600px
];

breakpoints.phone_portrait = breakpoints[0];
breakpoints.phone_landscape = breakpoints[1];
breakpoints.tablet_portrait = breakpoints[2];
breakpoints.tablet_landscape = breakpoints[3];
breakpoints.desktop_s = breakpoints[4];
breakpoints.desktop_m = breakpoints[5];
breakpoints.desktop_l = breakpoints[6];

export default breakpoints;
```

Afterwards I'm pulling them into the theme.js file. So far so good but once I try to reference them as follows:


```
H1.defaultProps = {
  fontFamily: 'teko_bold',
  fontWeight: 'normal',
  fontSize: {
    _: 1,
    phone_portrait: 2,
    phone_landscape: 3,
    tablet_portrait: 4,
    tablet_landscape: 5,
    desktop_s: 6,
    desktop_m: 7,
    desktop_l: 9,
  },
};
```

**things get stuck at `90em` - never reaching `100em`**. (The numbers for the fontsizes are just referencing the position of the actual value within the theme.js array for fontSizes)

However, if I prefix all of the values within breakpoints.js so the number will have the same length:


```
const breakpoints = [
  '021em', // 336px
  '035em', // 560px
  '045em', // 720px
  '064em', // 1024px
  '075em', // 1200px
  '090em', // 1400px
  '100em', // 1600px
];
```

**Everything works as expected and even the `100em` breakpoint gets picked up correctly**. But it's a weird thing to do...
