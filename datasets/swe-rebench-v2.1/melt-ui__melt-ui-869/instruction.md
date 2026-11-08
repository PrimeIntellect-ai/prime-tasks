🐛Bug: Calendar builder generates duplicate dates on some months when fixedWeeks is set to true
**Describe the bug**
Hello,

I've encountered this bug on the calendar builder (while using Bits UI which implements Melt UI) where the dates are being duplicated on some months (e.g. January 2024, September 2021). I've attached some screenshots outlining the issue (2 from Melt UI, one from Bits UI).

**To Reproduce**
Steps to reproduce the behavior:
1. Go to [https://melt-ui.com/docs/builders/calendar](https://melt-ui.com/docs/builders/calendar)
3. Scroll down to Fixed Weeks
4. See error (as outlined in the screenshots)

**Expected behavior**
Dates should not be duplicated

**Screenshots**
<img width="569" alt="Screenshot 2024-01-01 at 19 22 07" src="https://github.com/melt-ui/melt-ui/assets/17836403/ed419f8e-9e0e-4671-b3f2-794d9aad2d1f">
<img width="1205" alt="Screenshot 2024-01-01 at 10 12 54" src="https://github.com/melt-ui/melt-ui/assets/17836403/b41631d0-5e0b-407a-9e56-5e060b9d97e1">
<img width="1210" alt="Screenshot 2024-01-01 at 10 14 18" src="https://github.com/melt-ui/melt-ui/assets/17836403/95c318ea-d3cc-4422-b547-1e84c2bb0e55">

**Desktop (please complete the following information):**
 - OS: MacOS 14.2.1
 - Browser: Arc
 - Version: 1.21.2

**Additional context**
I'll also open a pull request fixing this issue, plus a couple of tests on the createMonths function to check for this particular bug.
