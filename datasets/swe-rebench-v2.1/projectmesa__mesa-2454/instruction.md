Bugs in SolaraViz?
I started working on #2427 and have run into three issues:

1. If the model takes one or more arguments and those arguments are not part of the user-controllable parameters that are set from the UI, stuff will crash immediately
2. Strangely, it crashes immediately even though we started SolaraViz with a valid model instance, so this points to a second bug: at the moment, the model shown after starting the UI is not the same as the original model with which the UI was initialized. Again, this is easy to reproduce. In the boltzman wealth model, in app.py, start the model with say a width and height of 20. Next, start Solara, and in the GUI, you'll see that the actual model has reverted back to 10 by 10 (as specified in `model_params`).
3. Seed is currently handled differently from other parameters. With #1940 merged, this is no longer needed, and seed can just be integrated into the user-specifiable parameters.
