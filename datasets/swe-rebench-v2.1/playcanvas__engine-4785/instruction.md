AnimEvents not dispatched after activeStateCurrentTime updated
Project : https://playcanvas.com/project/970223/overview/debug-seeking-animation

I want to be able to seek inside an animation. For now i just use activeStateCurrentTime.

For the use-case :
- i have added manually 3 AnimEvents of type "trick_step" with code in anim.js file
- an AnimEvent of type "animation_frame" is added for each 0.1s of the duration of the animation
- a final AnimEvent for the end of the animation (type "animation_end")

Steps to reproduce the working use-case :

- open JS console
- click on "load ollie"
- wait a little, you should see logs of AnimEvents frames, and the animation will stop on event "trick_step" with status "step_0"
- click on play, animation continue to event "trick_step" with status "step_0b"
- click play , and animation continue to event "trick_step" with status "step_1"
- click on play and after the animation ends.

Steps to reproduce the issue :

- click on "load ollie"
- wait a little, the animation will stop on event "trick_step" with status "step_0"
- click on "Next 2.7", the animation move to event "trick_step" with status "step_0b "(i just updated activeStateCurrentTime)
- click on play and after the animation ends but no logs for AnimEvents. But it is strange, they restarted a few seconds later...
