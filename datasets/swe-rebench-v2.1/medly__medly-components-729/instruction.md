bug: SingleSelect onBlur event not removing the focus
### Describe the bug
SingleSelect onBlur event not removing the focus, still able to open the drop-down after onBlur event using arrow keys

### To Reproduce
1. create a ref object and pass it to the SingleSelect component
2. perform blur event using ref, based on some event, or perform it in useEffect.
3. now open the dropdown using the down arrow key
4. You'll see the drop-down opening

### Expected behavior
blur event should remove the focus entirely form the field. It should not open drop down.

### Package versions
 - @medly-components/core : 6.26.2
