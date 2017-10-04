open GT
open MiniKanren
open Std
open Tester
open Printf

let ilist xs = list (!!) xs

let runaway_cell: (int List.ground, int logic List.logic) injected ref = ref (Obj.magic ())

let demo1 q =
  call_fresh (fun r ->
    runaway_cell := r;
    (q === q)
  )

let demo2 q =
  call_fresh (fun r ->
    (r === !!5) &&&
    conde [ (*(q === nil())
          ; *)(q === !runaway_cell)
          ]
    )

let intlist_reifier c xs =
  List.reify MiniKanren.reify c xs

let show_int = show(int)
let show_int_list = show(List.ground) show_int
let show2 xs = show(List.logic) (show(logic) show_int) xs

let runT n = runR intlist_reifier show_int_list show2 n
let () =
  runT 1 q qh ("?",(demo1));
  let () =
    try runT 2 q qh ("?",(demo2))
    with Failure s -> printf "Failure: \"%s\"\n%!" s
  in
  ()
