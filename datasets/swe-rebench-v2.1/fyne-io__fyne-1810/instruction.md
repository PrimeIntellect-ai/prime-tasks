Background color in the progress bar is missing
### Describe the bug:
<!-- A clear and concise description of what the bug is. -->
After updating from 1.3.3 to 1.4.3 I noticed some small theme changes.
But the most obvious change was that my background for my progress bar disappeared.

I had a short talk with @andydotxyz, and he mentioned it could be because the progress bar was previously hijacking the color from the buttons which I think have changed a bit in 1.4.x.


### To Reproduce:
Create a progress bar and render it. Then check the expected with a primary(moving part) and button color(background).
### Screenshots:
<!-- If applicable, add screenshots to help explain your problem. -->

Running in 1.3.3
![image](https://user-images.githubusercontent.com/2785213/103783929-9e0de200-5039-11eb-87cc-a97cdbb9b2c3.png)

Running in 1.4.3
![image](https://user-images.githubusercontent.com/2785213/103783664-4e2f1b00-5039-11eb-90b1-6ce33de76ad8.png)

### Device (please complete the following information):
 - OS: Raspbian 10
 - Version: 10 buster
 - Go version: go1.15.4 linux/arm
 - Fyne version: 1.4.3
