crm.company.contact.items.get возвращает только один элемент, а нужно несколько
Код, который я выполняю:

```
bx.get_by_ID("crm.company.contact.items.get", ['205364'])
```

Вот такой результат я получаю:

Только один контакт

Должно быть больше

Вот ПОЛНЫЕ логи, которые генерирует мой скрипт:

```
Starting get_by_ID((<fast_bitrix24.bitrix.Bitrix object at 0x000001F5C3777E00>, 'crm.company.contact.items.get', ['205364']), {})
fast_bitrix24 version: 1.8.3
No IPython found
  0%|          | 0/1 [00:00<?, ?it/s]Requesting {'method': batch, 'params': {'halt': 0, 'cmd': {'205364': 'crm.company.contact.items.get?ID=205364&'}}}
{'CONTACT_ID': 350354, 'SORT': 10, 'ROLE_ID': 0, 'IS_PRIMARY': 'Y'}
Response: {'result': {'result': {'205364': [{'CONTACT_ID': 350354, 'SORT': 10, 'ROLE_ID': 0, 'IS_PRIMARY': 'Y'}, {'CONTACT_ID': 369658, 'SORT': 10, 'ROLE_ID': 0, 'IS_PRIMARY': 'Y'}]}, 'result_error': [], 'result_total': [], 'result_next': [], 'result_time': {'205364': {'start': 1739205151.785116, 'finish': 1739205151.915156, 'duration': 0.13003993034362793, 'processing': 0.12938594818115234, 'date_start': '2025-02-10T19:32:31+03:00', 'date_finish': '2025-02-10T19:32:31+03:00', 'operating_reset_at': 1739205751, 'operating': 0.7021360397338867}}}, 'time': {'start': 1739205151.753569, 'finish': 1739205151.916085, 'duration': 0.16251611709594727, 'processing': 0.13108110427856445, 'date_start': '2025-02-10T19:32:31+03:00', 'date_finish': '2025-02-10T19:32:31+03:00', 'operating_reset_at': 1739205751, 'operating': 0}}
100%|██████████| 1/1 [00:00<00:00,  1.64it/s]
```

(Чтобы получить логи, нужно добавить в начало вашего скрипта:
```python
import logging

logging.getLogger('fast_bitrix24').addHandler(logging.StreamHandler())
```
