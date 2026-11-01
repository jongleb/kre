type t = {
  from : Kre_shared.Refined.Email.t;
  to_ : Kre_shared.Refined.Email.t;
  cc : Kre_shared.Refined.Email.t list;
  subject : string;
  text : string;
  html : string option;
}

let make ~from ~to_ ?(cc = []) ~subject ~text ?html () =
  { from; to_; cc; subject; text; html }

let address email = Kre_shared.Refined.Email.to_string email

let lines letter =
  let encoded header =
    match String.for_all (fun c -> Char.code c < 128) header with
    | true -> header
    | false -> "=?UTF-8?B?" ^ Base64.encode_string header ^ "?="
  in
  let date =
    let time = Unix.gmtime (Unix.gettimeofday ()) in
    Printf.sprintf "%s, %02d %s %d %02d:%02d:%02d +0000"
      (List.nth
         [ "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" ]
         time.tm_wday)
      time.tm_mday
      (List.nth
         [
           "Jan";
           "Feb";
           "Mar";
           "Apr";
           "May";
           "Jun";
           "Jul";
           "Aug";
           "Sep";
           "Oct";
           "Nov";
           "Dec";
         ]
         time.tm_mon)
      (time.tm_year + 1900) time.tm_hour time.tm_min time.tm_sec
  in
  let body text =
    List.map
      (fun line ->
        match String.ends_with ~suffix:"\r" line with
        | true -> String.sub line 0 (String.length line - 1)
        | false -> line)
      (String.split_on_char '\n' text)
  in
  [ "From: " ^ address letter.from; "To: " ^ address letter.to_ ]
  @ (match letter.cc with
    | [] -> []
    | cc -> [ "Cc: " ^ String.concat ", " (List.map address cc) ])
  @ [
      "Subject: " ^ encoded letter.subject; "Date: " ^ date; "MIME-Version: 1.0";
    ]
  @ Option.fold
      ~none:
        ([
           "Content-Type: text/plain; charset=utf-8";
           "Content-Transfer-Encoding: 8bit";
           "";
         ]
        @ body letter.text)
      ~some:(fun html ->
        let boundary =
          "kre-" ^ Digest.to_hex (Digest.string (letter.text ^ html))
        in
        [
          "Content-Type: multipart/alternative; boundary=\"" ^ boundary ^ "\"";
          "";
          "--" ^ boundary;
          "Content-Type: text/plain; charset=utf-8";
          "Content-Transfer-Encoding: 8bit";
          "";
        ]
        @ body letter.text
        @ [
            "--" ^ boundary;
            "Content-Type: text/html; charset=utf-8";
            "Content-Transfer-Encoding: 8bit";
            "";
          ]
        @ body html
        @ [ "--" ^ boundary ^ "--" ])
      letter.html

let render letter = String.concat "\r\n" (lines letter)

module type S = sig
  val send : t -> (unit, string) result Lwt.t
end

module Smtp (Config : sig
  val host : string
  val port : int
  val helo : string
end) =
struct
  let send letter =
    let open Lwt.Syntax in
    Lwt.catch
      (fun () ->
        let* addresses =
          Lwt_unix.getaddrinfo Config.host
            (string_of_int Config.port)
            [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ]
        in
        match addresses with
        | [] -> Lwt.return_error ("cannot resolve " ^ Config.host)
        | first :: _ ->
            Lwt_io.with_connection first.ai_addr (fun (input, output) ->
                let rec reply () =
                  let* line = Lwt_io.read_line input in
                  match String.length line with
                  | length when length > 3 && Char.equal line.[3] '-' ->
                      reply ()
                  | length ->
                      Lwt.return
                        ( Option.value ~default:0
                            (int_of_string_opt
                               (String.sub line 0 (min 3 length))),
                          line )
                in
                let step command expected =
                  let* () =
                    Option.fold ~none:Lwt.return_unit
                      ~some:(fun command ->
                        Lwt_io.write output (command ^ "\r\n"))
                      command
                  in
                  let* code, line = reply () in
                  match List.mem code expected with
                  | true -> Lwt.return_ok ()
                  | false -> Lwt.return_error ("smtp: " ^ line)
                in
                let ( let*? ) result next =
                  Lwt.bind result (function
                    | Ok () -> next ()
                    | Error message -> Lwt.return_error message)
                in
                let*? () = step None [ 220 ] in
                let*? () = step (Some ("EHLO " ^ Config.helo)) [ 250 ] in
                let*? () =
                  step
                    (Some ("MAIL FROM:<" ^ address letter.from ^ ">"))
                    [ 250 ]
                in
                let*? () =
                  List.fold_left
                    (fun previous recipient ->
                      let*? () = previous in
                      step
                        (Some ("RCPT TO:<" ^ address recipient ^ ">"))
                        [ 250; 251 ])
                    (Lwt.return_ok ()) (letter.to_ :: letter.cc)
                in
                let*? () = step (Some "DATA") [ 354 ] in
                let*? () =
                  step
                    (Some
                       (String.concat "\r\n"
                          (List.map
                             (fun line ->
                               match String.starts_with ~prefix:"." line with
                               | true -> "." ^ line
                               | false -> line)
                             (lines letter))
                       ^ "\r\n."))
                    [ 250 ]
                in
                step (Some "QUIT") [ 221 ]))
      (fun exn -> Lwt.return_error (Printexc.to_string exn))
end

module Outbox () = struct
  let letters = ref []

  let send letter =
    letters := letter :: !letters;
    Lwt.return_ok ()

  let sent () = List.rev !letters

  let controller =
    Controller.v
      ~spec:{ Spec.prefix = "/__kre"; version = None; routes = [] }
      [
        Route.v `GET
          (Routes.( @--> )
             Routes.(s "__kre" / s "mail" /? nil)
             (Route.handle ~status:`OK Route.Raw (fun _ ->
                  Lwt.map Result.ok
                    (Dream.html
                       (String.concat ""
                          ("<!doctype html><meta \
                            charset=utf-8><title>Mail</title><style>body{font:14px \
                            system-ui;margin:24px}article{border-top:1px solid \
                            #ccc;padding:8px \
                            0}pre{white-space:pre-wrap}</style><h1>Sent \
                            mail</h1>"
                          :: List.map
                               (fun letter ->
                                 Printf.sprintf
                                   "<article><b>%s</b><div>%s → \
                                    %s</div>%s</article>"
                                   (Dream.html_escape letter.subject)
                                   (Dream.html_escape (address letter.from))
                                   (Dream.html_escape (address letter.to_))
                                   (Option.fold
                                      ~none:
                                        ("<pre>"
                                        ^ Dream.html_escape letter.text
                                        ^ "</pre>")
                                      ~some:(fun html ->
                                        "<iframe srcdoc=\""
                                        ^ Dream.html_escape html
                                        ^ "\" \
                                           style=\"width:100%;border:0\"></iframe>")
                                      letter.html))
                               (List.rev !letters)))))));
      ]
end
