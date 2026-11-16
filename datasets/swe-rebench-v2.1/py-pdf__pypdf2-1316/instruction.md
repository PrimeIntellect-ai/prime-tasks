Invalid Text_extraction

## Environment

Which environment were you using when you encountered the problem?

```Python 3.10 - Windows ; PyPDF 2.10.4```

## Code + PDF
```python
import PyPDF2;p=PyPDF2.PdfReader("c:/main.pdf");p.pages[0].extract_text()
```

[main.pdf](https://github.com/py-pdf/PyPDF2/files/9472500/main.pdf)


## Traceback
reports:
'/a68/a105/a115/a112 /a101/a110/a115/a101 /a100/a105 /a97/a108/a103/a111/a114/a105/a116/a109/a105 /a101 /a115/a116/a114/a117/a116/a116/a117/a114/a101 /a100/a97/a116/a105\n/a76/a101/a111/a110/a97/a114/a100/a111 /a68/a101 /a70 /a97 /a118 /a101/a114/a105\n/a65/a46/a65/a46 /a50/a48/a50/a49/a47/a50/a48/a50/a50'

instead of
'Dispense di algoritmi e strutture dati
Leonardo De Faveri
A.A. 2021/2022'
