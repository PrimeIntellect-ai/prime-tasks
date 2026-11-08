Disable glow for progress animation
Is there a way to disable the white glow in the animation?

![image](https://github.com/ajalt/mordant/assets/33688601/6cf82800-1c9c-47d0-b191-58604399eca7)

Essentially I want something which looks like your example with static color which does advance without this animation.

![image](https://github.com/ajalt/mordant/assets/33688601/e027dd2a-abdb-457a-a583-71abd15a8bde)

### Additional contract requirements

`progressBar` exposes a per-bar `showPulse` option. Setting it to `false` disables the white glow in indeterminate rendering, while the bar continues to reflect subsequent progress updates. Omitting the option retains the existing indeterminate glow.
