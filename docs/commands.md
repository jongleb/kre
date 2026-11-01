# Commands

A command is code that needs the application context (database, services, config) but not HTTP. In Kre it is a function with `[@@command "description"]`: module parameters are providers that `[%wire]` passes in, labelled ones (`~count`, `?count`) are command-line options.

<!-- $MDX file=../examples/shelter/server/tasks.ml -->
```ocaml
let seed (module Cats : Cats_service.S) ?(count : int = 3) () : unit Lwt.t =
  Lwt_list.iter_s
    (fun number ->
      Lwt.map ignore
        (Cats.create
           {
             Create_cat_dto.name =
               Kre_shared.Validation.ok_exn
                 (Cat.Name.of_repr (Printf.sprintf "kitten %d" number));
             age = Kre_shared.Validation.ok_exn (Cat.Age.of_repr 0);
           }))
    (List.init count succ)
[@@command "Admit kittens to the shelter"]

let signup (module Users : Users_service.S)
    ~(email : Kre_shared.Refined.Email.t) ~(password : string) () : unit Lwt.t =
  Lwt.map
    (Result.fold
       ~ok:(fun (user : User.t) ->
         print_endline
           (Printf.sprintf "%s signed up as %s"
              (Kre_shared.Refined.Email.to_string user.email)
              (User.Role.to_string user.role)))
       ~error:(fun (error : Kre.Error.t) -> prerr_endline error.detail))
    (Users.signup { Login_dto.email; password })
[@@command "Create an account"]
```

Commands live in a separate file (not in a provider and not in a controller). `[%wire]` collects them into `app.commands`, and `Kre.App.run ~commands:app.commands` runs them:

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

- An option is parsed by the same module as a query parameter: `int`, `int64`, `float`, `bool`, `string` or `M.t` with `M : Kre_shared.Scalar.S` (`Cat.Id.t`, `Refined.Email.t`, a variant with `[@@deriving dto]`). Errors for all options are printed at once, exit code 2.
- `~(x : T)` is a required option, `?(x : T = default)` has a default value; `--x 3` and `--x=3` are equivalent.
- Before the command, providers' `on_start` runs (migrations); after it, `on_shutdown`. The server does not start.
- Without a command the binary runs as a server; `--emit-spec` and `--emit-openapi` work as before.
