Bug: Header Increment Doesn't Properly Decrement when Decremented Heading Is One Less than Next Heading
When I open  the button “Start Header Increment at Heading Level 2”

Original display：
```
## HHELLO
#### HHELLO
## HHELLO
## HHELLO
## HHELLO
```
Expected display content：
```
## HHELLO
### HHELLO
## HHELLO
## HHELLO
## HHELLO
```

Actual display content：
```
## HHELLO
### HHELLO
## HHELLO
### HHELLO
### HHELLO
```
I don't know if it's a problem with my setup, or a bug. There have been attempts to disable and reset other plugins, but this is still the case. The obsidian version used is 1.1.9. Looking forward to guidance, thanks!
