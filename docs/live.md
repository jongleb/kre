# Live loaders

В Nest такого нет; это IHP Auto Refresh. Страница перезапрашивает данные, когда кто-то изменил таблицы, из которых она читает. Кода подписки в приложении нет.

1. Хендлер объявляет таблицы, от которых зависит:

<!-- $MDX skip -->
```ocaml
let find_all (module Cats : Cats_service.S)
    ~(search : (Cat_search.t[@search])) () : Cat.t list Lwt.t = …
[@@get] [@@summary "List cats"] [@@live [ "cats" ]]
```

   `[@@live]` бывает только на GET и только со строками. Иначе — ошибка сборки.

2. Сервер публикует изменения сам:
   - драйвер (`Forge_db_mariadb.Sql`) видит SQL каждого запроса: `INSERT`/`UPDATE`/`DELETE` публикуют свою таблицу;
   - внутри `Db.transaction` и `[@@transactional]` изменения ждут commit, а после rollback пропадают;
   - хранилище без SQL зовёт `Forge.Live.publish [ "cats" ]`.

   Триггеры в БД не нужны, поэтому это работает и на MariaDB.

3. Канал: `Forge.Live.controller` — `GET /__forge/live?table=cats`, server-sent events, одно событие на изменение. Его подключают рядом с остальными контроллерами.

4. Клиент: `forge client` кладёт таблицы каждого live-маршрута в `Cats_client.Live`, роутер перезапускает loader при событии:

<!-- $MDX skip -->
```ocaml
Forge_client.Router.child ~live:Cats_client.Live.find_all root
  ~path:[%path "/cats"] ~search:Cat_search.codec
  ~loader:(fun () search -> Cats_client.find_all ~search)
  ~component:Pages.index
```

   Вне роутера — `Forge_client.Live.watch [ "cats" ] (fun table -> …)`, возвращает функцию отписки.

## Проверка списка

Забыть таблицу в `[@@live]` — значит тихо потерять обновления. Поэтому маршрут с `[@@live]` считает, какие таблицы прочитали его SQL-запросы (`SELECT … FROM/JOIN`):
- при `FORGE_ENV=test` недостающая таблица даёт 500 с текстом `/cats reads users; add it to [@@live]`, и e2e-тест падает;
- при `dev` (по умолчанию) это предупреждение в логе;
- в остальных профилях проверки нет.

Ограничения: один процесс, шина в памяти; таблицы ищутся по тексту SQL (`FROM a, b` видит только `a`); изменения, сделанные мимо приложения, не видны.

Проверено: `test/core` (шина, транзакции, проверка списка), `examples/cats/db/test` (commit и rollback на MariaDB), `examples/cats/client_js` (node получает `cats` по EventSource после чужого запроса).
