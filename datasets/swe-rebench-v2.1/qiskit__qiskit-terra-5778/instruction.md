bug in scheduling: gate lengths are wrongly attached
```py
from qiskit.circuit.library import HiddenLinearFunction
from qiskit.test.mock import FakeMontreal
from qiskit import transpile
circ = HiddenLinearFunction([[1, 1, 0], [1, 0, 1], [0, 1, 1]])
circ.draw('mpl')
sc = transpile(circ, FakeMontreal(), scheduling_method='asap')
```

here if you look inside sc.data you'll see that the duration of CX_{0,1} is set to the duration of CX_{1,2}=2560 dt, but it should be 1728 dt as reported by backend. Seems like the second CX over-rides the first CX somewhere.


```py
print(FakeMontreal().properties().gate_length('cx', (0, 1)) / FakeMontreal().configuration().dt) # 1728
print(FakeMontreal().properties().gate_length('cx', (1, 2)) / FakeMontreal().configuration().dt) # 2560
```

This bug causes the following obviously wrong timeline:
![image](https://user-images.githubusercontent.com/8622381/106604368-8ab54000-652d-11eb-9dc2-e51875dc5cac.png)
