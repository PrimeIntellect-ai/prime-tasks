Validar PIS
**Seu pedido de recurso está relacionado a um problema? Por favor, descreva.**
Verificar se uma String corresponde a um número de PIS válido, conforme as regras da numeração.

**Descreva a solução que você gostaria**
Chamar um novo utilitário passando uma String e receber um boolean indicando se a String é um número de PIS válido ou não.

**Descreva alternativas que você considerou**
Criar um novo utilitário `is_valid_pis`.
```python
def is_valid_pis(pis):
...
```
Exemplo de uso:
```python
from brutils import is_valid_pis

>>> is_valid_pis("12062828707")
True
>>> is_valid_pis("12066181422")
True
>>> is_valid_pis("12066181427")
False
>>> is_valid_pis("1206282")
False
```

**Contexto adicional**
- Não é necessário validar se o PIS existe de fato;
- https://pt.wikipedia.org/wiki/PIS/PASEP
- https://www.macoratti.net/alg_pis.htm
- https://www.geradorpis.com/
