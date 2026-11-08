grade_result() should not require a pass_if()
`grade_result()` returns an error message if it is called without at least one `pass_if()` statement. Here's an example from the `grading_demo()`, notice that I commented out the `pass_if()` statement to create this error

<img width="1703" alt="Screen Shot 2020-06-12 at 9 54 02 AM" src="https://user-images.githubusercontent.com/85014/84510180-c9427580-ac92-11ea-8c5e-14a11f3adc6f.png">

We should allow the user to call `grade_result()` without a `pass_if()` statement to simplify the case where there are many correct answers and the grader wants to screen for specific wrong answers. You can do this now by including `pass_if(~FALSE)` in the `grade_result()` call as a hack:

<img width="1703" alt="Screen Shot 2020-06-12 at 9 57 46 AM" src="https://user-images.githubusercontent.com/85014/84510504-37873800-ac93-11ea-98b9-dbdbfd95ff6f.png">

p.s. You can accomplish this by switching to `grade_conditions()` and flipping the logical sign of your tests, but that:
1. Seems like unnecessary mental gymnastics
2. Complicates my efforts to write a function that uses `grade_results()` to handle both cases 😈
