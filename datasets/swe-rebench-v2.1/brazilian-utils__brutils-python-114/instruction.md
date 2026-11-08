Criar mais testes para o utilitário is_valid_cnpj
Criar mais casos de teste para o utilitário is_valid_cnpj.

Alguns exemplos:
* testar quando o input não é uma string
* testar quando o input não tem o tamanho correto
* testar quando o input não contém apenas dígitos

Você pode utilizar o exemplo do CPF como base: https://github.com/brazilian-utils/brutils-python/blob/1b12ebfcbdef3715a1969139549d1038074f42aa/tests/test_cpf.py#L64

O algoritmo considerado para validação é este: https://www.geradorcnpj.com/algoritmo_do_cnpj.htm

Lembre-se também que você pode consultar como foi feita a implementação na biblioteca JS: https://github.com/brazilian-utils/brazilian-utils/tree/main/src/utilities/cnpj
