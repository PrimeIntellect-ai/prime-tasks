Propriedades de classe ficam como indefinidos quando seus valores são alterados utilizando operadores de incremento ou decremento
```js

classe Carteira {
  saldo: numero

  construtor() {
    isto.saldo = 100
  }

  depositar(dinheiro) {
    isto.saldo += dinheiro
  }
}

var carteira = Carteira();
carteira.depositar(200)
escreva(carteira.saldo);

```

![Image](https://github.com/user-attachments/assets/0fcdf797-e364-44e0-8fed-5b9a5757a236)
