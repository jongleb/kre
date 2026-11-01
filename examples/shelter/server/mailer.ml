module type S = sig
  val congratulate : Adoption.t -> (unit, string) result Lwt.t
end

module Make (Mail : Forge.Mail.S) : S = struct
  let congratulate (adoption : Adoption.t) =
    Mail.send
      (Forge.Mail.make
         ~from:
           (Forge_shared.Validation.ok_exn
              (Forge_shared.Refined.Email.of_repr "shelter@shelter.test"))
         ~to_:
           (Forge_shared.Validation.ok_exn
              (Forge_shared.Refined.Email.of_repr "staff@shelter.test"))
         ~subject:"A cat found a home"
         ~text:
           (Printf.sprintf "user %s adopted cat %s"
              (User.Id.to_string adoption.user_id)
              (Cat.Id.to_string adoption.cat_id))
         ())
  [@@job Queues.congratulate]
end
