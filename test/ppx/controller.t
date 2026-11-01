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
  >     (Cat.t, Kre.Error.t) result Lwt.t =
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
    ~body:(body : Create_cat_dto.t) : (Cat.t, Kre.Error.t) result Lwt.t=
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
                (Kre.Route.segment (module Breed) ":breed"))
             (Kre.Route.segment (module Kre_shared.Scalar.Int) ":id"))
          Routes.nil
      let create () =
        Routes.(/?) (Routes.(/) (Routes.s "v2") (Routes.s "cats")) Routes.nil
      let remove () =
        Routes.(/?)
          (Routes.(/) (Routes.(/) (Routes.s "v2") (Routes.s "cats"))
             (Kre.Route.segment (module Kre_shared.Scalar.Int) ":id"))
          Routes.nil
    end
  let spec : Kre.Spec.t =
    {
      Kre.Spec.prefix = "/cats";
      version = (Some 2);
      routes =
        [{
           Kre.Spec.verb = `GET;
           path = "/v2/cats";
           name = "list";
           params =
             [{
                Kre.Spec.name = "limit";
                label = "limit";
                location = (Kre.Spec.Query Kre.Spec.Optional);
                value =
                  {
                    Kre.Spec.type_ = "int";
                    module_ = "Kre_shared.Scalar.Int";
                    schema =
                      ((let module M = Kre_shared.Scalar.Int in M.t_jsonschema))
                  }
              };
             {
               Kre.Spec.name = "q";
               label = "q";
               location = (Kre.Spec.Query Kre.Spec.Optional);
               value =
                 {
                   Kre.Spec.type_ = "string";
                   module_ = "Kre_shared.Scalar.String";
                   schema =
                     ((let module M = Kre_shared.Scalar.String in
                         M.t_jsonschema))
                 }
             };
             {
               Kre.Spec.name = "tags";
               label = "tags";
               location = (Kre.Spec.Query Kre.Spec.Repeated);
               value =
                 {
                   Kre.Spec.type_ = "string";
                   module_ = "Kre_shared.Scalar.String";
                   schema =
                     ((let module M = Kre_shared.Scalar.String in
                         M.t_jsonschema))
                 }
             }];
           body = None;
           returns =
             (Kre.Spec.Json
                {
                  Kre.Spec.type_ = "Cat.t list";
                  module_ = "Kre_shared.Json.List (Cat)";
                  schema =
                    ((let module M = (Kre_shared.Json.List)(Cat) in
                        M.t_jsonschema))
                });
           status = (Dream.int_to_status 200);
           summary = None;
           description = None;
           live = [];
           guards = ["Auth.signed_in"]
         };
        {
          Kre.Spec.verb = `GET;
          path = "/v2/cats/:breed/:id";
          name = "show";
          params =
            [{
               Kre.Spec.name = "id";
               label = "id";
               location = Kre.Spec.Path;
               value =
                 {
                   Kre.Spec.type_ = "int";
                   module_ = "Kre_shared.Scalar.Int";
                   schema =
                     ((let module M = Kre_shared.Scalar.Int in M.t_jsonschema))
                 }
             };
            {
              Kre.Spec.name = "breed";
              label = "breed";
              location = Kre.Spec.Path;
              value =
                {
                  Kre.Spec.type_ = "Breed.t";
                  module_ = "Breed";
                  schema = ((let module M = Breed in M.t_jsonschema))
                }
            }];
          body = None;
          returns =
            (Kre.Spec.Json
               {
                 Kre.Spec.type_ = "Cat.t";
                 module_ = "Cat";
                 schema = ((let module M = Cat in M.t_jsonschema))
               });
          status = (Dream.int_to_status 200);
          summary = None;
          description = None;
          live = [];
          guards = ["Auth.signed_in"]
        };
        {
          Kre.Spec.verb = `POST;
          path = "/v2/cats";
          name = "create";
          params = [];
          body =
            (Some
               {
                 Kre.Spec.type_ = "Create_cat_dto.t";
                 module_ = "Create_cat_dto";
                 schema = ((let module M = Create_cat_dto in M.t_jsonschema))
               });
          returns =
            (Kre.Spec.Json
               {
                 Kre.Spec.type_ = "Cat.t";
                 module_ = "Cat";
                 schema = ((let module M = Cat in M.t_jsonschema))
               });
          status = (Dream.int_to_status 201);
          summary = None;
          description = None;
          live = [];
          guards = ["Auth.signed_in"; "Auth.admin"]
        };
        {
          Kre.Spec.verb = `DELETE;
          path = "/v2/cats/:id";
          name = "remove";
          params =
            [{
               Kre.Spec.name = "id";
               label = "id";
               location = Kre.Spec.Path;
               value =
                 {
                   Kre.Spec.type_ = "int";
                   module_ = "Kre_shared.Scalar.Int";
                   schema =
                     ((let module M = Kre_shared.Scalar.Int in M.t_jsonschema))
                 }
             }];
          body = None;
          returns = Kre.Spec.Unit;
          status = (Dream.int_to_status 204);
          summary = None;
          description = None;
          live = [];
          guards = ["Auth.signed_in"]
        }]
    }
  let register ((module Cats)  : (module Cats_service.S))
    ((module Log)  : (module Logger.S)) =
    Kre.Controller.v ~middleware:[Logger.use] ~spec
      [Kre.Route.v ~middleware:[Cache.use] `GET
         (Routes.(@-->) (Paths.list ())
            (Kre.Route.handle ~status:(Dream.int_to_status 200)
               ~guards:[Auth.signed_in]
               (Kre.Route.Json (module (Kre_shared.Json.List)(Cat)))
               (fun __kre_request ->
                  let open Kre.Route.Syntax in
                    let* __kre_arg_limit =
                      Kre.Route.query (module Kre_shared.Scalar.Int)
                        Kre_shared.Presence.Optional "limit" __kre_request
                     in
                    let* __kre_arg_q =
                      Kre.Route.query (module Kre_shared.Scalar.String)
                        Kre_shared.Presence.Optional "q" __kre_request
                     in
                    let* __kre_arg_tags =
                      Kre.Route.query (module Kre_shared.Scalar.String)
                        Kre_shared.Presence.Repeated "tags" __kre_request
                     in
                    Kre.Route.ok
                      (list (module Cats) ?limit:__kre_arg_limit ?q:__kre_arg_q
                         ~tags:__kre_arg_tags ()))));
      Kre.Route.v `GET
        (Routes.(@-->) (Paths.show ())
           (fun __kre_arg_breed __kre_arg_id ->
              Kre.Route.handle ~status:(Dream.int_to_status 200)
                ~guards:[Auth.signed_in] (Kre.Route.Found (module Cat))
                (fun __kre_request ->
                   Kre.Route.ok
                     (show (module Cats) ~id:__kre_arg_id
                        ~breed:__kre_arg_breed))));
      Kre.Route.v `POST
        (Routes.(@-->) (Paths.create ())
           (Kre.Route.handle ~status:(Dream.int_to_status 201)
              ~guards:[Auth.signed_in; Auth.admin]
              (Kre.Route.Json (module Cat))
              (fun __kre_request ->
                 let open Kre.Route.Syntax in
                   let* __kre_arg_3 = Extract.ip __kre_request
                    in
                   let* __kre_arg_user = Auth.current __kre_request
                    in
                   let* __kre_arg_body =
                     Kre.Route.body (module Create_cat_dto) __kre_request
                    in
                   create (module Cats) (module Log) __kre_request __kre_arg_3
                     ~user:__kre_arg_user ~body:__kre_arg_body)));
      Kre.Route.v `DELETE
        (Routes.(@-->) (Paths.remove ())
           (fun __kre_arg_id ->
              Kre.Route.handle ~status:(Dream.int_to_status 204)
                ~guards:[Auth.signed_in] Kre.Route.Unit
                (fun __kre_request ->
                   Kre.Route.ok (remove (module Cats) ~id:__kre_arg_id ()))))]
