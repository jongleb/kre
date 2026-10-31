val structure :
  ctxt:Ppxlib.Expansion_context.Deriver.t ->
  Ppxlib.rec_flag * Ppxlib.type_declaration list ->
  Ppxlib.structure

val signature :
  ctxt:Ppxlib.Expansion_context.Deriver.t ->
  Ppxlib.rec_flag * Ppxlib.type_declaration list ->
  Ppxlib.signature
