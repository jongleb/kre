type t = {
  spec : Spec.t;
  middleware : Dream.middleware list;
  routes : Route.t list;
}

let v ?(middleware = []) ~spec routes = { spec; middleware; routes }
