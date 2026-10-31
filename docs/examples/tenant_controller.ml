[@@@controller "tenant"]
[@@@host ":account.example.com"]

let whoami ~(account : (string[@host_param "account"])) () : string Lwt.t =
  Lwt.return account
[@@get]
