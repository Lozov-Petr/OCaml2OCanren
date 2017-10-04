open GT
open MiniKanren
open Std
open Tester

let show_nat_list = GT.(show List.ground @@ show Nat.ground)
let show_nat      = GT.(show Nat.ground)

(* Relational minimum/maximum (for nats only) *)
let minmaxo a b min max = Nat.(
    conde
      [ (min === a) &&& (max === b) &&& (a <= b)
      ; (max === a) &&& (min === b) &&& (a >  b)
      ]
  )

let () =
    run_exn GT.(show bool)  (-1)   q  qh ("?",(fun q   -> Nat.leo (nat 1) (nat 2) q));
    run_exn GT.(show bool)  (-1)   q  qh ("?",(fun q   -> Nat.leo (nat 2) (nat 1) q));
    run_exn GT.(show bool)  (-1)   q  qh ("?",(fun q   -> Nat.gto (nat 1) (nat 2) q));
    run_exn GT.(show bool)  (-1)   q  qh ("?",(fun q   -> Nat.gto (nat 2) (nat 1) q));

    run_exn show_nat  (-1)  qr qrh ("?",(fun q r -> minmaxo (nat 1) (nat 2)  q r ));
    ()
