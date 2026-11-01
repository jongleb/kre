module Id = Kre_shared.Id.Make ()

(** What a user may do: admins add cats and rename any of them. *)
module Role = struct
  type t = Admin | Member [@@deriving dto]
end

type t = {
  id : Id.t; [@primary] [@auto] [@column int]
  email : Kre_shared.Refined.Email.t; [@column string] [@size 255] [@unique]
  role : Role.t; [@column string] [@size 16]
}
[@@deriving table ~name:"users", dto]
