Regression: Spinbox siPrefix with dimensionless quantities impossible
### Short description
`siPrefix` is very useful when working with very high or low numbers, and I appreciate this a lot, sometimes having every prefix range from `n` to `k` in one UI. Sometimes the quantities are dimensionless, sometimes the units are not known to the program or tracked otherwise.

Since pyqtgraph 0.11, spinboxes need an SI `suffix` when using `siPrefix`. This has the apparent consequence that one cannot work with dimensionless numbers (or unitless numbers) anymore.
I could not find an issue explaining the reasoning behind this change, only commit 6b798ffed856d8b2f7d53544ca4c480b2f7911d5 in #410 by @campagnola.

I have not found a way to work around this issue. I've tried passing `''` or a space `' '` into `suffix`, but that did not help.

Can you please fix this regression and re-enable using prefix-only with the Spinbox?
Should it be important for users to specifically switch on this behaviour, maybe an approach is to have `None` as a default for  `suffix`, and supply `suffix=''` to enable working with dimensionless numbers, which would be fine by me.

### Code to reproduce
```python
import pyqtgraph
from pyqtgraph.Qt import QtGui

app = QtGui.QApplication([])

w = pyqtgraph.QtGui.QMainWindow()
g = pyqtgraph.QtGui.QWidget()
l = pyqtgraph.QtGui.QHBoxLayout()
label = pyqtgraph.QtGui.QLabel()
label.setText('Reynolds number')
s = pyqtgraph.SpinBox(siPrefix=True)
display = pyqtgraph.QtGui.QLabel()
display.setText('value')
s.valueChanged.connect(lambda v: display.setText(str(v)))

g.setLayout(l)
w.setCentralWidget(g)

l.addWidget(label)
l.addWidget(s)
l.addWidget(display)

w.show()
app.exec()
```

### Expected behavior
The old behaviour behaves as expected, enabling use of prefixes with dimensionless quantities:
![image](https://user-images.githubusercontent.com/327442/98345859-81433700-2015-11eb-9753-efa704f3a075.png)

In another application, I am heavily using the siPrefix to enable easy entry and display of high/low numbers (with unity only being implicit due to device interface), and it works very well with 0.10:
![image](https://user-images.githubusercontent.com/327442/98347653-f9aaf780-2017-11eb-8c67-9995826adb15.png)

### Real behavior
The new behaviour sinc 0.11 does not accept prefix-only.
Also (I suspect that this is another bug), sometimes it selects the value when pressing enter, leaving the prefix in place but not in the value
![image](https://user-images.githubusercontent.com/327442/98345666-42ad7c80-2015-11eb-9384-7c791bedc0bf.png)
sometimes strips an entered prefix without warning
![image](https://user-images.githubusercontent.com/327442/98345765-6375d200-2015-11eb-8ac7-7234be718ab4.png)

### Tested environment(s)

 * PyQtGraph version: 0.10 and 0.11.0. respectively
 * Qt Python binding: PyQt5 5.9.2 Qt 5.9.6
 * Python version: 3.7
 * NumPy version: 1.19.2
 * Operating system: Windows
 * Installation method: conda
