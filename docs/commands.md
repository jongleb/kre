# Commands

Symfony: `#[AsCommand]`. Rails: rake-задачи и `rails runner`. Spring: `CommandLineRunner`. IHP: Scripts. Везде это код, которому нужен контекст приложения (база, сервисы, конфиг), но не HTTP. В Forge — функция с `[@@command "описание"]`: модульные параметры — провайдеры, которые передаст `[%wire]`, помеченные (`~count`, `?count`) — опции командной строки.

<!-- $MDX file=../examples/shelter/server/tasks.ml -->
```ocaml
let seed (module Cats : Cats_service.S) ?(count : int = 3) () : unit Lwt.t =
  Lwt_list.iter_s
    (fun number ->
      Lwt.map ignore
        (Cats.create
           {
             Create_cat_dto.name =
               Forge_shared.Validation.ok_exn
                 (Cat.Name.of_repr (Printf.sprintf "kitten %d" number));
             age = Forge_shared.Validation.ok_exn (Cat.Age.of_repr 0);
           }))
    (List.init count succ)
[@@command "Admit kittens to the shelter"]

let signup (module Users : Users_service.S)
    ~(email : Forge_shared.Refined.Email.t) ~(password : string) () : unit Lwt.t
    =
  Lwt.map
    (Result.fold
       ~ok:(fun (user : User.t) ->
         print_endline
           (Printf.sprintf "%s signed up as %s"
              (Forge_shared.Refined.Email.to_string user.email)
              (User.Role.to_string user.role)))
       ~error:(fun (error : Forge.Error.t) -> prerr_endline error.detail))
    (Users.signup { Login_dto.email; password })
[@@command "Create an account"]
```

Команды живут в отдельном файле (не в провайдере и не в контроллере). `[%wire]` собирает их в `app.commands`, `Forge.App.run ~commands:app.commands` запускает:

```
$ main.exe help
commands:
  seed --count  Admit kittens to the shelter
  signup --email --password  Create an account
$ main.exe seed --count 2
$ main.exe signup --email=root@shelter.test --password whiskers1
root@shelter.test signed up as admin
$ main.exe signup --email nope
--email: must be an email address
--password is required
```

- Опция разбирается тем же модулем, что и query-параметр: `int`, `int64`, `float`, `bool`, `string` или `M.t` с `M : Forge_shared.Scalar.S` (`Cat.Id.t`, `Refined.Email.t`, вариант с `[@@deriving dto]`). Ошибки всех опций выводятся сразу, код выхода 2.
- `~(x : T)` — обязательная опция, `?(x : T = default)` — со значением по умолчанию; `--x 3` и `--x=3` равны.
- Перед командой выполняются `on_start` провайдеров (миграции), после — `on_shutdown`. Сервер не стартует.
- Без команды бинарь работает как сервер; `--emit-spec` и `--emit-openapi` — как раньше.
