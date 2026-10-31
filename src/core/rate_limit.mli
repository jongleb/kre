val middleware :
  limit:int ->
  window:float ->
  ?key:(Dream.request -> string) ->
  ?clock:(unit -> float) ->
  unit ->
  Dream.middleware
