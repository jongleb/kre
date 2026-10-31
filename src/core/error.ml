type status = [ Dream.client_error | Dream.server_error | `Unprocessable_Entity ]

type t = {
  status : status;
  code : string;
  type_ : string;
  detail : string;
  extensions : (string * Jsonkit.t) list;
}

exception E of t

type handler = Dream.request -> t -> Dream.response Lwt.t

let make ~status ~code ?type_ ?(extensions = []) detail =
  {
    status;
    code;
    type_ = Option.value type_ ~default:("urn:forge:error:" ^ code);
    detail;
    extensions;
  }

let bad_request ?extensions detail =
  make ~status:`Bad_Request ~code:"bad_request" ?extensions detail

let unauthorized detail = make ~status:`Unauthorized ~code:"unauthorized" detail
let forbidden detail = make ~status:`Forbidden ~code:"forbidden" detail
let not_found detail = make ~status:`Not_Found ~code:"not_found" detail
let conflict detail = make ~status:`Conflict ~code:"conflict" detail

let unprocessable errors =
  make ~status:`Unprocessable_Entity ~code:"validation"
    ~extensions:[ ("errors", Forge_shared.Validation.to_json errors) ]
    "validation failed"

let internal detail =
  make ~status:`Internal_Server_Error ~code:"internal" detail

let to_dream_status = function
  | `Unprocessable_Entity -> `Status 422
  | #Dream.client_error as status -> (status :> Dream.status)
  | #Dream.server_error as status -> (status :> Dream.status)

let to_json ~instance error =
  `Assoc
    ([
       ("type", `String error.type_);
       ("title", `String (Dream.status_to_string (to_dream_status error.status)));
       ("status", `Int (Dream.status_to_int (to_dream_status error.status)));
       ("detail", `String error.detail);
       ("instance", `String instance);
     ]
    @ error.extensions)

let to_response request error =
  Dream.respond
    ~status:(to_dream_status error.status)
    ~headers:[ ("Content-Type", "application/problem+json") ]
    (Jsonkit.to_string (to_json ~instance:(Dream.target request) error))

let fail error = Lwt.fail (E error)
