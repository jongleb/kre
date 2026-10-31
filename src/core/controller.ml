type t = {
  spec : Spec.t;
  middleware : Dream.middleware list;
  routes : Route.t list;
  error_handler : Error.handler option;
  host : string option;
}

let v ?(middleware = []) ?error_handler ?host ~spec routes =
  { spec; middleware; routes; error_handler; host }
