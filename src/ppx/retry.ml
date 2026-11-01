open Ppxlib
open Ast_builder.Default

let mapper =
  object
    inherit Ast_traverse.map as super

    method! value_binding binding =
      let binding = super#value_binding binding in
      let find name =
        List.find_opt
          (fun (attribute : attribute) ->
            String.equal attribute.attr_name.txt name)
          binding.pvb_attributes
      in
      let payload (attribute : attribute) =
        match attribute.attr_payload with
        | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] ->
            Some expression
        | _ -> None
      in
      match (find "retry", find "backoff") with
      | None, None -> binding
      | None, Some backoff ->
          Location.raise_errorf ~loc:backoff.attr_loc
            "[@@@@backoff] sets the pause between retries; add [@@@@retry 3]"
      | Some retry, backoff ->
          let loc = retry.attr_loc in
          let attempts =
            match payload retry with
            | Some
                ({ pexp_desc = Pexp_constant (Pconst_integer (_, None)); _ } as
                 attempts) ->
                attempts
            | Some _ | None ->
                Location.raise_errorf ~loc
                  "[@@@@retry] takes the number of attempts: [@@@@retry 3]"
          in
          let pause =
            Option.map
              (fun (attribute : attribute) ->
                match payload attribute with
                | Some
                    ({ pexp_desc = Pexp_constant (Pconst_float _); _ } as
                     seconds) ->
                    seconds
                | Some _ | None ->
                    Location.raise_errorf ~loc:attribute.attr_loc
                      "[@@@@backoff] takes the first pause in seconds: \
                       [@@@@backoff 0.1]")
              backoff
          in
          let wrap body =
            pexp_apply ~loc [%expr Forge.Retry.run]
              (Option.fold ~none:[]
                 ~some:(fun pause -> [ (Labelled "backoff", pause) ])
                 pause
              @ [
                  (Labelled "attempts", attempts);
                  (Nolabel, [%expr fun () -> [%e body]]);
                ])
          in
          {
            binding with
            pvb_expr =
              (match binding.pvb_expr.pexp_desc with
              | Pexp_function
                  ((_ :: _ as params), constraint_, Pfunction_body body) ->
                  {
                    binding.pvb_expr with
                    pexp_desc =
                      Pexp_function
                        (params, constraint_, Pfunction_body (wrap body));
                  }
              | _ ->
                  Location.raise_errorf ~loc
                    "[@@@@retry] repeats a call; put it on a function: let f x \
                     = … [@@@@retry 3]");
            pvb_attributes =
              List.filter
                (fun (attribute : attribute) ->
                  not (List.mem attribute.attr_name.txt [ "retry"; "backoff" ]))
                binding.pvb_attributes;
          }
  end

let structure items = mapper#structure items
