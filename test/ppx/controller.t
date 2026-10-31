A controller with every kind of parameter.

  $ cat > cats_controller.ml <<'ML'
  > [@@@controller "cats"]
  > [@@@version 2]
  > [@@@use [ Logger.use ]]
  > [@@@guards [ Auth.signed_in ]]
  > 
  > let helper x = x + 1
  > 
  > let list (module Cats : Cats_service.S) ?(limit : int = 20)
  >     ?(q : string option) ~(tags : string list) () : Cat.t list Lwt.t =
  >   Cats.list ~limit ?q ~tags ()
  > [@@get] [@@use [ Cache.use ]]
  > 
  > let show (module Cats : Cats_service.S) ~(id : int) ~(breed : Breed.t) :
  >     Cat.t option Lwt.t =
  >   Cats.find id breed
  > [@@get ":breed/:id"]
  > 
  > let create (module Cats : Cats_service.S) (module Log : Logger.S)
  >     (req : Dream.request) (ip : string [@from Extract.ip])
  >     ~(user : User.t [@guard Auth.current]) ~(body : Create_cat_dto.t) :
  >     (Cat.t, Forge.Error.t) result Lwt.t =
  >   Log.info req ip user;
  >   Cats.add body
  > [@@post] [@@status 201] [@@guards [ Auth.admin ]]
  > 
  > let remove (module Cats : Cats_service.S) ~(id : int) () : unit Lwt.t =
  >   Cats.remove id
  > [@@delete ":id"]
  > ML
  $ ./pp.exe -impl cats_controller.ml
  let helper x = x + 1
  let list ((module Cats)  : (module Cats_service.S)) ?limit:((limit : int)=
    20) ?q:(q : string option) ~tags:(tags : string list) () :
    Cat.t list Lwt.t= Cats.list ~limit ?q ~tags ()
  let show ((module Cats)  : (module Cats_service.S)) ~id:(id : int)
    ~breed:(breed : Breed.t) : Cat.t option Lwt.t= Cats.find id breed
  let create ((module Cats)  : (module Cats_service.S))
    ((module Log)  : (module Logger.S)) (req : Dream.request)
    (ip : ((string)[@from Extract.ip]))
    ~user:(user : ((User.t)[@guard Auth.current]))
    ~body:(body : Create_cat_dto.t) : (Cat.t, Forge.Error.t) result Lwt.t=
    Log.info req ip user; Cats.add body
  let remove ((module Cats)  : (module Cats_service.S)) ~id:(id : int) () :
    unit Lwt.t= Cats.remove id
  module Paths =
    struct
      let list () =
        Routes.(/?) (Routes.(/) (Routes.s "v2") (Routes.s "cats")) Routes.nil
      let show () =
        Routes.(/?)
          (Routes.(/)
             (Routes.(/) (Routes.(/) (Routes.s "v2") (Routes.s "cats"))
                (Forge.Route.segment (module Breed) ":breed"))
             (Forge.Route.segment (module Forge_shared.Scalar.Int) ":id"))
          Routes.nil
      let create () =
        Routes.(/?) (Routes.(/) (Routes.s "v2") (Routes.s "cats")) Routes.nil
      let remove () =
        Routes.(/?)
          (Routes.(/) (Routes.(/) (Routes.s "v2") (Routes.s "cats"))
             (Forge.Route.segment (module Forge_shared.Scalar.Int) ":id"))
          Routes.nil
    end
  let spec : Forge.Spec.t =
    {
      Forge.Spec.prefix = "/cats";
      version = (Some 2);
      routes =
        [{
           Forge.Spec.verb = `GET;
           path = "/v2/cats";
           name = "list";
           params =
             [{
                Forge.Spec.name = "limit";
                label = "limit";
                location = (Forge.Spec.Query Forge.Spec.Optional);
                value =
                  {
                    Forge.Spec.type_ = "int";
                    module_ = "Forge_shared.Scalar.Int";
                    schema =
                      ((let module M = Forge_shared.Scalar.Int in
                          M.t_jsonschema))
                  }
              };
             {
               Forge.Spec.name = "q";
               label = "q";
               location = (Forge.Spec.Query Forge.Spec.Optional);
               value =
                 {
                   Forge.Spec.type_ = "string";
                   module_ = "Forge_shared.Scalar.String";
                   schema =
                     ((let module M = Forge_shared.Scalar.String in
                         M.t_jsonschema))
                 }
             };
             {
               Forge.Spec.name = "tags";
               label = "tags";
               location = (Forge.Spec.Query Forge.Spec.Repeated);
               value =
                 {
                   Forge.Spec.type_ = "string";
                   module_ = "Forge_shared.Scalar.String";
                   schema =
                     ((let module M = Forge_shared.Scalar.String in
                         M.t_jsonschema))
                 }
             }];
           body = None;
           returns =
             (Forge.Spec.Json
                {
                  Forge.Spec.type_ = "Cat.t list";
                  module_ = "Forge_shared.Json.List (Cat)";
                  schema =
                    ((let module M = (Forge_shared.Json.List)(Cat) in
                        M.t_jsonschema))
                });
           status = (Dream.int_to_status 200);
           summary = None;
           description = None;
           guards = ["Auth.signed_in"]
         };
        {
          Forge.Spec.verb = `GET;
          path = "/v2/cats/:breed/:id";
          name = "show";
          params =
            [{
               Forge.Spec.name = "id";
               label = "id";
               location = Forge.Spec.Path;
               value =
                 {
                   Forge.Spec.type_ = "int";
                   module_ = "Forge_shared.Scalar.Int";
                   schema =
                     ((let module M = Forge_shared.Scalar.Int in M.t_jsonschema))
                 }
             };
            {
              Forge.Spec.name = "breed";
              label = "breed";
              location = Forge.Spec.Path;
              value =
                {
                  Forge.Spec.type_ = "Breed.t";
                  module_ = "Breed";
                  schema = ((let module M = Breed in M.t_jsonschema))
                }
            }];
          body = None;
          returns =
            (Forge.Spec.Json
               {
                 Forge.Spec.type_ = "Cat.t";
                 module_ = "Cat";
                 schema = ((let module M = Cat in M.t_jsonschema))
               });
          status = (Dream.int_to_status 200);
          summary = None;
          description = None;
          guards = ["Auth.signed_in"]
        };
        {
          Forge.Spec.verb = `POST;
          path = "/v2/cats";
          name = "create";
          params = [];
          body =
            (Some
               {
                 Forge.Spec.type_ = "Create_cat_dto.t";
                 module_ = "Create_cat_dto";
                 schema = ((let module M = Create_cat_dto in M.t_jsonschema))
               });
          returns =
            (Forge.Spec.Json
               {
                 Forge.Spec.type_ = "Cat.t";
                 module_ = "Cat";
                 schema = ((let module M = Cat in M.t_jsonschema))
               });
          status = (Dream.int_to_status 201);
          summary = None;
          description = None;
          guards = ["Auth.signed_in"; "Auth.admin"]
        };
        {
          Forge.Spec.verb = `DELETE;
          path = "/v2/cats/:id";
          name = "remove";
          params =
            [{
               Forge.Spec.name = "id";
               label = "id";
               location = Forge.Spec.Path;
               value =
                 {
                   Forge.Spec.type_ = "int";
                   module_ = "Forge_shared.Scalar.Int";
                   schema =
                     ((let module M = Forge_shared.Scalar.Int in M.t_jsonschema))
                 }
             }];
          body = None;
          returns = Forge.Spec.Unit;
          status = (Dream.int_to_status 204);
          summary = None;
          description = None;
          guards = ["Auth.signed_in"]
        }]
    }
  let register ((module Cats)  : (module Cats_service.S))
    ((module Log)  : (module Logger.S)) =
    Forge.Controller.v ~middleware:[Logger.use] ~spec
      [Forge.Route.v ~middleware:[Cache.use] `GET
         (Routes.(@-->) (Paths.list ())
            (Forge.Route.handle ~status:(Dream.int_to_status 200)
               ~guards:[Auth.signed_in]
               (Forge.Route.Json (module (Forge_shared.Json.List)(Cat)))
               (fun __forge_request ->
                  let open Forge.Route.Syntax in
                    let* __forge_arg_limit =
                      Forge.Route.query (module Forge_shared.Scalar.Int)
                        Forge_shared.Presence.Optional "limit" __forge_request
                     in
                    let* __forge_arg_q =
                      Forge.Route.query (module Forge_shared.Scalar.String)
                        Forge_shared.Presence.Optional "q" __forge_request
                     in
                    let* __forge_arg_tags =
                      Forge.Route.query (module Forge_shared.Scalar.String)
                        Forge_shared.Presence.Repeated "tags" __forge_request
                     in
                    Forge.Route.ok
                      (list (module Cats) ?limit:__forge_arg_limit
                         ?q:__forge_arg_q ~tags:__forge_arg_tags ()))));
      Forge.Route.v `GET
        (Routes.(@-->) (Paths.show ())
           (fun __forge_arg_breed __forge_arg_id ->
              Forge.Route.handle ~status:(Dream.int_to_status 200)
                ~guards:[Auth.signed_in] (Forge.Route.Found (module Cat))
                (fun __forge_request ->
                   Forge.Route.ok
                     (show (module Cats) ~id:__forge_arg_id
                        ~breed:__forge_arg_breed))));
      Forge.Route.v `POST
        (Routes.(@-->) (Paths.create ())
           (Forge.Route.handle ~status:(Dream.int_to_status 201)
              ~guards:[Auth.signed_in; Auth.admin]
              (Forge.Route.Json (module Cat))
              (fun __forge_request ->
                 let open Forge.Route.Syntax in
                   let* __forge_arg_3 = Extract.ip __forge_request
                    in
                   let* __forge_arg_user = Auth.current __forge_request
                    in
                   let* __forge_arg_body =
                     Forge.Route.body (module Create_cat_dto) __forge_request
                    in
                   create (module Cats) (module Log) __forge_request
                     __forge_arg_3 ~user:__forge_arg_user
                     ~body:__forge_arg_body)));
      Forge.Route.v `DELETE
        (Routes.(@-->) (Paths.remove ())
           (fun __forge_arg_id ->
              Forge.Route.handle ~status:(Dream.int_to_status 204)
                ~guards:[Auth.signed_in] Forge.Route.Unit
                (fun __forge_request ->
                   Forge.Route.ok (remove (module Cats) ~id:__forge_arg_id ()))))]
