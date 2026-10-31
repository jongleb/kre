(** Which compiler the deriver runs for; Melange gets no table code. *)
type target = Native | Melange

val target : target ref

val structure :
  ctxt:Ppxlib.Expansion_context.Deriver.t ->
  Ppxlib.rec_flag * Ppxlib.type_declaration list ->
  string option ->
  Ppxlib.structure
