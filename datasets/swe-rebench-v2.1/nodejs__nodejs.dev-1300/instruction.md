bug: opening navigation menu scrolls whole page
## Description

When opening the navigation menu on mobile screens on `/learn` pages, the whole page gets scrolled due to animation, instead of just the navigation part.

### Steps to reproduce

Go to https://nodejs.dev/learn/where-does-npm-install-the-packages and then open and close the navigation menu,

### Expected result

Upon closing the navigation menu, you should be able to continue from where you left for navigation.

### Actual result

The whole page scrolls to the end.

### Environment

- OS Version: Android 11
- Browser Version: Chrome 90

### Additional contract requirements

- The public function `calcNavScrollParams(height: number, navElement: HTMLElement)` in module `src/util/scrollTo` returns an object whose `scrollWindow` field is always the provided `navElement`.
