type t = {
  spec : Spec.t;
  middleware : Dream.middleware list;
  routes : Route.t list;
  error_handler : Error.handler option;
}

let v ?(middleware = []) ?error_handler ~spec routes =
  { spec; middleware; routes; error_handler }
