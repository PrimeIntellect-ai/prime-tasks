Gerar CEPs aleatórios e válidos
Implementar um utilitário que retorna um CEP aleatório válido

### Additional contract requirements

- Add a public function `generate() -> str` in module `brutils.cep`.
- It takes no inputs.
- It returns an 8-character string containing only digits (0-9), representing a syntactically valid CEP.
- It produces a random CEP by generating eight random digits, so repeated calls yield varying results.
