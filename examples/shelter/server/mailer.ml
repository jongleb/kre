module type S = sig
  val congratulate : Adoption.t -> (unit, string) result Lwt.t
end

module Make (Mail : Kre.Mail.S) : S = struct
  let congratulate (adoption : Adoption.t) =
    Mail.send
      (Kre.Mail.make
         ~from:
           (Kre_shared.Validation.ok_exn
              (Kre_shared.Refined.Email.of_repr "shelter@shelter.test"))
         ~to_:
           (Kre_shared.Validation.ok_exn
              (Kre_shared.Refined.Email.of_repr "staff@shelter.test"))
         ~subject:"A cat found a home"
         ~text:
           (Printf.sprintf "user %s adopted cat %s"
              (User.Id.to_string adoption.user_id)
              (Cat.Id.to_string adoption.cat_id))
         ())
  [@@job Queues.congratulate]
end
