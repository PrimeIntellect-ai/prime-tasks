Gerar número de PIS válido e aleatório
**Seu pedido de recurso está relacionado a um problema? Por favor, descreva.**
Gerar um número de PIS válido e aleatório.

**Descreva a solução que você gostaria**
- Chamar um novo utilitário que retorna um número de PIS válido e aleatório.
- Sem formatação

**Descreva alternativas que você considerou**
- Criar um novo utilitário generate_pis:
```python
def generate_pis():
...
```
Exemplo de uso:
```
from brutils import generate_pis

>>> generate_pis()
"12042644708"
>>> generate_pis()
"12021423567"
```

**Contexto adicional**
- https://pt.wikipedia.org/wiki/PIS/PASEP
- https://www.macoratti.net/alg_pis.htm

### Additional contract requirements

- Provide a public function `generate()` in module `brutils.pis` that takes no inputs and returns a valid PIS/PASEP number as an 11-digit string without formatting.
