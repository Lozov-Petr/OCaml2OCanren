open Printf
open MiniKanren
open Std
open Tester

let show_nat        = GT.show(Nat.ground)
let show_bool       = GT.show(Bool.ground)

let show_nat_llist  = GT.show(List.ground) (GT.show(Nat.ground))
let show_bool_llist = GT.show(List.ground) (GT.show(Bool.ground))
let show_option_nat = GT.(show option  (show Nat.ground))

let (?$) = nat
let nats = nat_list
let bools = list (!!)

let sumo = List.foldro Nat.addo ?$0

let () =
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.noto Bool.truo  q                       ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.noto Bool.falso q                       ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.noto q          Bool.truo               ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.oro   Bool.falso Bool.falso q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.oro   Bool.falso Bool.truo  q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.oro   Bool.truo  Bool.falso q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.oro   Bool.truo  Bool.truo  q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.ando  Bool.falso Bool.falso q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.ando  Bool.falso Bool.truo  q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.ando  Bool.truo  Bool.falso q            ));
  run_exn show_bool        1    q  qh ("?",(fun q     -> Bool.ando  Bool.truo  Bool.truo  q            ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.addo ?$0 ?$1 q                             ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.addo ?$1 q   ?$3                           ));
  run_exn show_nat         3   qr qrh ("?",(fun q r   -> Nat.addo q   r   q                             ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.mulo ?$1 ?$2 q                             ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.mulo ?$3 q   ?$6                           ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.mulo ?$3 q   ?$6                           ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.mulo ?$3 ?$0 q                             ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> Nat.mulo q   ?$5 ?$0                           ));
  run_exn show_nat         3    q  qh ("?",(fun q     -> Nat.mulo q   ?$0 ?$0                           ))

let () =
  run_exn show_nat         1    q  qh ("?",(fun q     -> sumo (nats []) q                               ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> sumo (nats [3;1;2]) q                          ));
  run_exn show_nat         1    q  qh ("?",(fun q     -> sumo (?$0 % (?$1 % (q %< ?$3))) ?$6            ));
  ()

let () =
  run_exn show_nat         1    q   qh ("?",(fun q     -> List.lengtho (nats [1;2;3;4]) q                    ));
  run_exn show_nat         1    q   qh ("?",(fun q     -> List.lengtho (list (!!) [(); (); ()]) q    ));
  run_exn show_nat         1    q   qh ("?",(fun q     -> List.lengtho (bools [false; true]) q               ));
  run_exn show_nat         1    q   qh ("?",(fun q     -> List.lengtho (nats [4;3;2;1;0]) q                  ));
  run_exn show_nat_llist   1    q   qh ("?",(fun q     -> List.lengtho q ?$0                                 ));

  run_exn show_bool        1    q   qh ("?",(fun q     -> List.anyo (bools [false; false; true]) q               ));
  run_exn show_bool        1    q   qh ("?",(fun q     -> List.anyo (bools [false; false]) q                     ));

  run_exn show_bool        1    q   qh ("?",(fun q     -> List.allo (bools [true; false; true]) q                ));
  run_exn show_bool        1    q   qh ("?",(fun q     -> List.allo (Bool.truo % (q %< Bool.truo)) Bool.truo     ));
  run_exn show_bool      (-1) qrs qrsh ("?",(fun q r s -> List.allo (Bool.truo % (q %< r)) s                     ))

let _ =
  run_exn show_nat_llist    1    q  qh ("?",(fun q     -> List.mapo (Nat.addo ?$1) (nats [0;1;2]) q              ));
  run_exn show_nat_llist    1    q  qh ("?",(fun q     -> List.mapo (Nat.addo ?$2) q (nats [4;3;2])              ));
  run_exn show_nat          1    q  qh ("?",(fun q     -> List.mapo (Nat.addo q) (nats [1;2;3]) (nats [4;5;6])   ));
  run_exn show_nat          1    q  qh ("?",(fun q     -> List.mapo (Nat.mulo q) (nats [1;2;3]) (nats [2;4;6])   ));
  run_exn show_nat          1   qr qrh ("?",(fun q r   -> List.mapo (Nat.mulo q) (nats [1;2]) (?$2 %< r)         ));
  run_exn show_nat_llist    1    q  qh ("?",(fun q     -> List.mapo (===) (nats [1;2;3]) q                       ));
  run_exn show_nat          1    q  qh ("?",(fun q     -> List.mapo (===) (nats [1;2;3]) (?$1 % (?$2 %< q))      ));
  run_exn show_bool_llist   1    q  qh ("?",(fun q     -> List.mapo Bool.noto (bools [true;false;true;]) q       ));
  run_exn show_bool_llist   1    q  qh ("?",(fun q     -> List.mapo Bool.noto (bools []) q                       ));

  run_exn show_nat_llist  (-1)   q  qh ("?",(fun q     -> List.filtero (eqo ?$2) (nats [0;1;2;3]) q              ));
  run_exn show_option_nat   1    q  qh ("?",(fun q     -> List.lookupo (eqo ?$1) (nats [0;2;1;3]) q              ))

let show_nat_list   = GT.(show List.ground @@ show Nat.ground)
let show_natl_listl = GT.(show List.logic  @@ show Nat.logic)

let runN n = runR Nat.reify show_nat (GT.show(Nat.logic)) n
let runL n = runR (List.reify Nat.reify) show_nat_list show_natl_listl n

let _freeVars =
  runN         3   qr qrh ("?",(fun q r   -> Nat.mulo q   r   q             ));
  runL      (-1)    q  qh ("?",(fun q     -> List.lengtho q ?$3             ))
