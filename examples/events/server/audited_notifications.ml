[@@@decorates Notifications.S]

module Make (Notifications : Notifications.S) = struct
  let send address = Notifications.send address @ [ "audit " ^ address ]
end
