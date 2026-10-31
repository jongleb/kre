val params :
  ctxt:Ppxlib.Expansion_context.Deriver.t ->
  Ppxlib.rec_flag * Ppxlib.type_declaration list ->
  string option ->
  Ppxlib.structure

val search :
  ctxt:Ppxlib.Expansion_context.Deriver.t ->
  Ppxlib.rec_flag * Ppxlib.type_declaration list ->
  Ppxlib.structure

val path : Ppxlib.Extension.t
