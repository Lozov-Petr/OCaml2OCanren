open GT

open OCanren
open OCanren.Std
open Tester

open Test_nat
open Test_mul

(*************************************************)

let show_number num =
  let rec helper = function
  | O   -> 0
  | S x -> 1  + (helper x)
  in
  string_of_int @@ helper num

let rec of_int i = if i = 0 then o () else s @@ of_int @@ i - 1

(** For high order conversion **)
let mul a b c = mul_o ((===) a) ((===) b) c

let () =
  run_exn show_number (1) q qh ("answers", fun q ->
    mul (of_int 8) (of_int 5) q
  )
