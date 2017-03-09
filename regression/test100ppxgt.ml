type token_env = int [@@deriving gt {show; gmap} ]

let () = print_endline @@ GT.(show token_env) 5

type 'a logic =
| Var   of GT.int * 'a logic GT.list
| Value of 'a



type ('a, 'l) llist = Nil | Cons of 'a * 'l

type 'a lnat = O | S of 'a
