ui.Slider: intial value sometimes (randomly) not honored
With the following MWE and flexx from git:

```
from flexx import app, ui
class Sliderbug(ui.Widget):
    def init(self):
        ui.Slider(min=3,max=10,value=6,step=1.)
if __name__=='__main__':
    app.launch(Sliderbug)
    app.run()

```

I sometimes get the initial value wrong, about 50%-50%, running exactly the same code. I can also verify that in the first (buggy) case the slider gives "1" as its value (rather than 3, which is the minimum):

![slider-bug](https://cloud.githubusercontent.com/assets/1029876/18514001/06a3771e-7a90-11e6-8531-67dd2413cd59.png)

![slider-ok](https://cloud.githubusercontent.com/assets/1029876/18514007/0e0e735a-7a90-11e6-8e58-eb080c3e3b7f.png)
