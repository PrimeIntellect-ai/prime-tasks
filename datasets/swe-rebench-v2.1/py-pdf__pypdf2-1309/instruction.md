Arabic text is extracted in the wrong order
There is a big problem with arabic text extraction.

If we have a string that says (مرحبا هذه تجربة) the PyPDF2 extract_text function returned it like : (ةبرجت هذه ابحرم).

## Environment

```bash
$ python -m platform
Windows-10-10.0.19044-SP0

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
2.10.3
```

## Code + PDF

This is a minimal, complete example that shows the issue with [file.pdf](https://github.com/py-pdf/PyPDF2/files/9440583/file.pdf):

```python
from PyPDF2 import PdfReader

reader = PdfReader("file.pdf")

text = ""
for page in reader.pages:
    text += page.extract_text()
    break
print(text)
```

It gives:

```
Ang-L1+sociology-globalisation:

 :مﻗر ة رﻀﺎحمﻟا1              : ﺔمﻟوﻌﻟاglobalization :

 : ﺔمﻟوﻌﻠﻟ ﺔ�خ�رﺎتﻟا ﺔ�فﻠخﻟا
 : ﺢﻠطصمﻟا  ﺢﻠطصمﻟا ﺔمﻟوﻌﻟاmondialisation  ﺔمﻠكﻟا نﻤmonde  ﺔ�نیﺘﻼﻟا ﺔمﻠكﻟا نﻤ ةدمتسﻤmundus

 ﻲنﻌﺘ ﻲتﻟاوunivers.  و ،globe  ﺔ�نیﺘﻼﻟا ﺔمﻠكﻟا نﻤglobus   .ءﻲشﻟا م�مﻌﺘ ﻲنﻌﺘو
: ﺎﻬﻔ�رﻌﺘ
  نودﺒ وأ دصﻘ� ﻰﻌسﺘ ﻲتﻟا تا روطتﻟا و تادجتسمﻟا " ﺎﻬﻨﺄ� ﺔمﻟوﻌﻟا بﺎت� ﻒﻟؤﻤ :زرﺘاو موكﻟﺎﻤ ﺎﻬﻓ رﻌ�.دﺤاو ﻲمﻟﺎﻋ ﻊمتجﻤ ﻲﻓ مﻟﺎﻌﻟا نﺎكﺴ ﺞﻤد ﻰﻟإ دصﻗ
Globalization  ﻞكﻟا ﻞمش�ﻟ ﻪﺘ رﺌاد ﻊ�ﺴوﺘ و ءﻲشﻟا م�مﻌﺘ : ﻲنﻌﺘ ﻲﻬﻓ."ادﺤاو ﺎمﻟﺎﻋ مﻟﺎﻌﻟا ﻞﻌﺠ "يأ ﻞﺴا ر زیﺘ زﻟ رﺎشﺘ ﻲك� رﻤﻷا وﻫ ﺔمﻟوﻌﻠﻟ ﻰﻟوﻻا ئدﺎ�مﻟا ﻊﻀوﺒ مﺎﻗ نﻤ لوأ charles taze russell
  " ﺢﻠطصﻤ ﻰﻟإ ﻞﺼوﺘ نﻤ لوأ دﻌ� ﻪﻨا ﺎم� ،تﺎ� رﺸ بﺤﺎﺼ و ﺎ�ﻟﺎمﺴأ ر نﺎ� نأ دﻌ� ﺎسﻗ ﺢ�ﺼأ يذﻟا  مﺎﻋ ﻲﻓ"ﺔﻗﻼمﻌﻟا تﺎ� رشﻟا1897 .
ا ﻲﻓ كﻟذ� ﺢﻠطصمﻟا ﻞمﻌتﺴأ  نﺎﺘ ری�و� رﺎ�ﺒ ف رط نﻤ ة رﻤ لوﻷ ﺔ�سﻨ رﻔﻟpierre de coubertin  ﻲ ﻓ  ة د �ر ﺠle figaro
  م ﺎ ﻋ13  ربمس�د1904 .
ﻲسﻨ رﻔﻟا ﻲﻓا رﻐجﻟا خ رؤمﻟا بﺎت� ﻲﻓ رﻬظ مﺜ    vincent copdepny  ت� رﺘأ لوﺒ ل بﺎت� ﻲﻓ رشﻨ ، paul otlet   ﺔنﺴ1916 "ﻲنیﺠ نﺎﻓ دﻟوﻨ رأ" دﯿ ﻰﻠﻋ مﺜ.arnold von gennep ,1933   ظ و ﻲﻓا رﻐجﻟا بﺎت� ﻲﻓ كﻟذ� ت رﻬle géographe laurent carroué    ﻰﻟإ ﺔﻓﺎﻀﻹﺎ� ،يوورﺎ� نا روﻟ   ﻪ�ﺸور ﻲﻏguy rocher     نﺎﻫوﻟ كﺎﻤ لﺎﺸ رﺎﻤ دﯿ ﻰﻠﻋ و ، ﺎﻬﻔ� رﻌﺘ لوﺎﺤ يذﻟاmarshall Mc luhan   ﻪﻔﻟؤﻤ ﻲﻓvillage Global "   ﻲﻨﺎ�ﺴﻹا ز� رﯿ ﺎمﻛmanuel castell’s    و ﺔ�دﺎصتﻗﻻا ﻞﻤاوﻌﻟا ﻰﻠﻋ ﻻا ز� ر�و ، ﺔ�عﺎمتﺠjohn urry
   ﺦﻟإ...،ﺔ�ﺴﺎ�سﻟا و ﺔ�فﺎﻘثﻟا ،ﺔ�دﺎصتﻗﻻا ، ﺔ�ﻨﺎسﻨﻹا تا رییﻐتﻟا ﻰﻠﻋ
: ةﺄشنﻟا : ﺔمﻟوﻌﻟا روﻬظ بﺎ�ﺴأ
: ﺔ�دﺎصتﻗﻹا ﻞﻤاوﻌﻟا
 ﺔ�ﻨﺎط� ربﻟا ﺔ�ق رشﻟا دنﻬﻟا ﺔ� رﺸ س�ﺴﺄﺘ .
 : ﺔ�ﻟﺎﻤو ﺔ� رﺎجﺘ ، ﺔ�عﺎنﺼ ، ﺔ�ﺠﺎتﻨإ ﻞﻤاوﻋ
- ة روثﻟا و ﺔ�عﺎنصﻟا ة روثﻟا.ﺔ�ﺠوﻟونكتﻟا
- .ﺔ�ﻟﺎمﻟا تﺎسﺴؤمﻟا لﻼﺨ نﻤ ﻲﻟﺎﻤ دﺎصتﻗا روﻠبﺘ ق� رط نﻋ لاوﻤﻷا سوؤر
-.لاوﻤﻷا سوؤر لﺎﻘتﻨاو ﺔ� رﺎجتﻟا ﺔ� رحﻟا ةدﺎ� ز
```

but it's partially reversed, e.g. the beginning

![image](https://user-images.githubusercontent.com/1658117/187275192-6f4d1c84-ae37-4d84-89f5-8c453e6d3033.png)

should be

```
‫‪:‬‬ ‫‪globalization‬‬ ‫‪:‬‬ ‫العولمة   ‫‪1:‬‬ ‫رقم‪:‬‬ ‫المحاضرة‬
‬
```
