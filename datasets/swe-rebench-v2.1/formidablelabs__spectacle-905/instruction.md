Keyboard controls don't work on Linux
Keyboard controls only work for Windows and Mac.
I am using an Ubuntu and when I start my presentation and press one of the following combinations nothing happens.
`Alt` + `O`
`Alt` + `P`
`Alt` + `F`

### Additional contract requirements

- Add a public function `isLinux()` in module `src/utils/detect-platform.js`. It takes no arguments and returns `true` when `navigator.platform` contains the substring "linux" (case-insensitive), and `false` otherwise.
