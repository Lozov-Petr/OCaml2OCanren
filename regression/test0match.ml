open Printf
open MiniKanren
open ImplicitPrinters
open Tester.M

module Value = struct
  type t = Vint of int
         | Vtuple of t list
         | Vconstructor of string * t list
end
type varname = string
type pat = Pany
         | Pvar of varname
         | Pconstant of int
         | Ptuple of pat list
         | Pconstructor of string * pat option
         (* | Por of pat * pat *)

implicit module Show_pat : (SHOW with type t = pat) = struct
    type t = pat
    let rec show = function
      | Pany -> "_"
      | Pvar s -> s
      | Pconstant x -> string_of_int x
      | Ptuple ps -> sprintf "(%s)" @@ String.concat "," @@ List.map show ps
      | Pconstructor (name,None) -> name
      | Pconstructor (name,Some p) -> sprintf "%s %s" name (show p)
      (* | Por (p1,p2) -> sprintf "%s | %s" (show p1) (show p2) *)
end
(*
let pat_of_parsetree root =
  let open Longident in
  let open Asttypes in
  let open Parsetree in
  let rec helper p =
    match p.ppat_desc with
    | Ppat_any -> Pany
    | Ppat_var {txt; _} -> Pvar txt
    | Ppat_constant (Const_int n) -> Pconstant n
    (* | Ppat_or (x,y) -> Por (helper x, helper y) *)
    | Ppat_construct ({txt=Lident name;_},None)   -> Pconstructor (name, None)
    | Ppat_construct ({txt=Lident name;_},Some x) -> Pconstructor (name, Some (helper x))
    | Ppat_or (p1,p2) -> Por (helper p1, helper p2)
    | Ppat_tuple ps -> Ptuple (List.map helper ps)
    | _ ->
       let b = Buffer.create 20 in
       let fmt = Format.formatter_of_buffer b in
       let () = Pprintast.pattern fmt p in
       let () = Format.pp_print_flush fmt () in
       failwith
         (sprintf "Can't convert this OCaml pattern to mini one:\n" ^ (Buffer.contents b))
  in
  helper root

let () =
  let f x = print_endline @@ show (pat_of_parsetree x) in
  f [%pat? [] ];
  f [%pat? _::_ ];
  f [%pat? 1::2::[] ];
  ()
 *)


let (!) = embed

module Nat = struct
  type t = O | S of t logic
  let show = function
    | O -> "O"
    | S n -> sprintf "S (%s)" (show_logic_naive n)
end
implicit module Show_nat : (SHOW with type t = Nat.t) = Nat

let nat_of_int n : Nat.t =
  if n<0 then failwith "bad argument"
  else
    let rec helper acc n =
      if n=0 then acc
      else helper (Nat.S !acc) (n-1)
    in
    helper Nat.O n

let is_positive_nat n = fresh (_zero) (n === !(Nat.S _zero))
let is_nonnegative_nat n = fresh (_zero) (conde [(n === !(Nat.S _zero));  (n === !Nat.O) ])

module Peano_int = struct
    type t = bool * Nat.t logic
    let show : t -> string = fun (p,n) ->
      if p then show n
      else "-" ^ (show n)
    let of_int n =
      if n>=0 then (true, !(nat_of_int n) )
      else (false, !(nat_of_int (-n)) )
end
(*implicit module Show_peano_int: (SHOW with type t = Peano_int.t) = Peano_int*)

let is_positive_peano p =
  let open Nat in
  fresh (_zero) (p === !(true, !(S _zero)) )

let is_negative_peano p =
  let open Nat in
  fresh (_zero) (p === !(false, !(S _zero)) )

let is_non_negative_peano p =
  let open Nat in
  conde [ p === !(true, !O)
        ; p === !(false, !O)
        ; is_positive_peano p
        ]

let is_non_positive_peano p =
  let open Nat in
  conde [ p === !(true, !O)
        ; p === !(false, !O)
        ; is_negative_peano p
        ]

module MiniLambda = struct
  type structured_constant = (* Const_int  *) Peano_int.t
  type lambda_switch =
    { sw_numconsts: int;                  (* Number of integer cases *)
      sw_consts: (int * lambda) list;     (* Integer cases *)
      sw_numblocks: int;                  (* Number of tag block cases *)
      sw_blocks: (int * lambda) list;     (* Tag block cases *)
      sw_failaction : lambda option}      (* Action to take if failure *)
  and lambda =
    | Lvar of Ident.t logic
    | Lconst of structured_constant logic
    (* | Lapply of lambda logic * lambda logic llist *)
    (* | Lfunction of function_kind * Ident.t list * lambda *)
    (* | Llet of Lambda.let_kind * Ident.t * lambda logic * lambda logic *)
    (* | Lletrec of (Ident.t * Lambda.lambda) list * Lambda.lambda *)
    (* | Lprim of Lambda.primitive * Lambda.lambda list *)
    (* | Lswitch of lambda * lambda_switch *)
    (* | Lstringswitch of Lambda.lambda * (string * Lambda.lambda) list * *)
    (*                    Lambda.lambda option *)
    (* | Lstaticraise of int * Lambda.lambda list *)
    (* | Lstaticcatch of lambda * (int * Ident.t list) * lambda *)
    (* | Ltrywith of lambda * Ident.t * Lambda.lambda *)
    | Lifthenelse of (lambda logic * lambda logic * lambda logic)
    (* | Lsequence of lambda * lambda *)
    (* | Lwhile of Lambda.lambda * Lambda.lambda *)
    (* | Lfor of Ident.t * Lambda.lambda * Lambda.lambda * *)
    (*         Asttypes.direction_flag * Lambda.lambda *)
    (* | Lassign of Ident.t * lambda *)
    (* | Lsend of Lambda.meth_kind * Lambda.lambda * Lambda.lambda * *)
    (*   Lambda.lambda list * Location.t *)
    (* | Levent of Lambda.lambda * Lambda.lambda_event *)
    (* | Lifused of Ident.t * Lambda.lambda *)
end
(*
implicit module Show_Structured_constant : (SHOW with type t=MiniLambda.structured_constant) =
struct
  type t = MiniLambda.structured_constant
  let show =
    let rec helper = function
      | (* MiniLambda.Const_int *) n -> string_of_int n
    in
    helper
end *)
implicit module Show_MiniLambda : (SHOW with type t = MiniLambda.lambda) =
struct
  type t = MiniLambda.lambda
  let show =
    let open MiniLambda in
    let rec helper = function
      (* | Lconst ((Var _) as l) -> sprintf "Lconst %s" (show_logic_naive l) *)
      | Lconst l -> sprintf "Lconst %s" (show_logic_naive l)
      | Lifthenelse (cond,ifb,elseb) -> sprintf "if %s then %s else %s fi" (show_logic_naive cond) (show_logic_naive ifb) (show_logic_naive elseb)
      | _ -> "<not implemented XXX>"
    in
    helper
end

module type INTABLE = sig
    type t
    val of_int : t -> Peano_int.t
end
implicit module Int_as_intable : (INTABLE with type t = int) = struct
  type t = int
  let of_int = Peano_int.of_int
end
implicit module Peano_as_intable : (INTABLE with type t = Peano_int.t) = struct
  type t = Peano_int.t
  let of_int n = n
end

let make_const {X: INTABLE} (n:X.t) : MiniLambda.structured_constant = X.of_int n

let is_positive_const lam =
  let open MiniLambda in
  fresh (n)
        (lam === !(Lconst n))
        (is_positive_peano n)

let is_nonnegative_const lam =
  let open MiniLambda in
  fresh n
    (lam === !(Lconst n))
    (is_non_negative_peano n)

let is_negative_const lam =
  let open MiniLambda in
  fresh n
    (lam === !(Lconst n))
    (is_negative_peano n)

let is_non_positive_const lam =
  let open MiniLambda in
  fresh n
    (lam === !(Lconst n))
    (is_non_positive_peano n)

(* let () = print_endline @@ show MiniLambda.(!(Const_int 11)) *)

exception No_var_in_env
let eval_lambda
    (env: Ident.t logic -> MiniLambda.structured_constant)
    (lam_ast: MiniLambda.lambda) =
  let open MiniLambda in
  let open Tester.M in
  let rec evalo l (ans: MiniLambda.lambda logic) =
    printf "evalo '%s' '%s'\n%!" (show l) (show ans);

    conde
      [ fresh (id1)
          (l   === !(Lvar id1))
          (ans === !(Lconst !(env id1)) )
      ; fresh (_c1) (l === !(Lconst _c1)) &&& (l === ans)
      ; fresh (cond ifb elseb) (
          ( l === !(Lifthenelse (cond, ifb, elseb)) ) &&&
          (* evaluating condition *)
          (fresh (rez)
                 (evalo cond rez)
                 (conde
                    [ (is_positive_const rez) &&& (ifb === ans)
                    ; (is_negative_const rez) &&& (elseb === ans)
                    ])) )
      ]
  in
  let open Tester.M.ConvenienceStream in
  let open ImplicitPrinters in
  (* let stream = run one @@ evalo !(Lconst !(make_const 1)) in *)
  let stream = run one @@ evalo !lam_ast in
  (* printf "stream = '%s'\n%!" (MiniKanren.generic_show stream); *)
  let _ = MiniKanren.Stream.take ~n:1 stream in

  let xs = stream
           |> MiniKanren.Stream.take ~n:1
           |> List.map (fun (_logger, (_q,_constraints)) -> _q)
  in
  (* let xs = stream (fun var1 -> var1 1 |> List.map (fun (_logger, (_q,_constraints)) -> _q) ) *)
  (* in *)
  (* let (_:int list) = xs in *)
  (* let (_q,stream) = Tester.M.run (call_fresh (fun q st ->  evalo !(Lconst !(make_const 1)) q st,q) ) in *)
  (* let _ = Stream.take ~n:1 stream in *)
  printf "answers: %d\n%!" (List.length xs);
  List.iter (fun x -> print_endline @@ show x) xs

let () =
  let open MiniLambda in
  let env : Ident.t logic -> structured_constant  =
    fun x ->
      Peano_int.of_int 1
  in

  let lam1 = Lifthenelse ( !(Lconst !(make_const 1))
                         , !(Lconst !(make_const (Peano_int.of_int 2)) )
                         , !(Lconst !(make_const 3))
                         ) in
  let lam2 = Lconst !(make_const 1) in

  (* let () = eval_lambda env lam2 in *)
  let () = eval_lambda env lam1 in
  ()

let eval_match (what: Value.t) pats  =
  let distinct_sets : 'a list -> 'a list -> bool = fun xs ys ->
    let rec helper = function
    | [] -> true
    | x::xs when List.mem x ys -> false
    | _::xs -> helper xs
    in
    helper xs
  in
  let merge_subs xs ys =
    if distinct_sets xs ys then List.append xs ys
    else failwith "not distinct sets"
  in
  (* `what` should be tuple with no free variables *)
  let rec match_one what patt =
    let open Value in
    match what,patt with
    (* | _ , Por _ -> failwith "or pattern not implemented" *)
    | Vint _, Pany -> Some []
    | Vint n, Pvar name -> Some [ (name,Vint n) ]
    | Vint n, Pconstant m when n=m -> Some []
    | Vint _, Pconstant _ -> None
    | Vint _, Ptuple _
    | Vint _, Pconstructor _ -> None
    | Vtuple xs, Ptuple ys when List.length xs <> List.length ys -> None
    | Vtuple xs, Ptuple ys ->
       List.combine xs ys
       |> ListLabels.fold_left
            ~init:(Some [])
            ~f:(fun acc (x,y) ->
                                   match acc with
                                   | Some subs -> begin
                                       match match_one x y with
                                       | Some subs2 when distinct_sets subs subs2 ->
                                          Some (merge_subs subs subs2)
                                       | _ -> failwith "can't merge subs  in matching tuple"
                                     end
                                   | None -> None)
    | Vtuple _,_ -> None
    | Vconstructor (name,_), Pconstructor (name2,_) when name<>name2 ->
       None
    | Vconstructor (_,[x]), Pconstructor(_,Some p) -> match_one x p
    | Vconstructor (_,[x]), Pconstructor(_,None)   -> None
    | Vconstructor (_,xs),  Pconstructor(_,Some (Ptuple ys)) ->
       match_one (Vtuple xs) (Ptuple ys)
    | Vconstructor _, Pconstructor _ -> None
    | Vconstructor _, _ -> None

  in
  let module S = struct
      type subs = (string * Value.t) list
      exception Answer of subs * Value.t
  end in
  try List.iter (fun (pat, right) ->
                match match_one what pat with
                | Some subs -> raise (S.Answer (subs,right))
                | None -> ()) pats;
      None
 with S.Answer (subs, right) -> Some right



let test_eval_match () =
  let open Value in
  let v1 = Vint 1 in

  assert (eval_match (Vint 1) [ (Pany, Vint 1) ] = Some (Vint 1) );
  assert (eval_match (Vint 1) [ (Pvar "x", Vint 1) ] = Some (Vint 1) );
  assert (eval_match (Vint 1) [ (Pvar "x", Vint 1) ] = Some (Vint 1) );
  assert (eval_match (Vtuple [Vint 1;Vint 2]) [ (Pvar "x", Vint 1) ] = None );
  assert (eval_match (Vtuple [Vint 1;Vint 2])
                     [ (Ptuple [Pvar "x"; Pconstant 2], Vint 3) ] = Some (Vint 3) );
  assert (eval_match  (Vtuple [Vconstructor("Some", [Vint 1]); Vint 2])
                     [(Ptuple [Pconstructor("Some", Some Pany); Pconstant 2], Vint 3) ] = Some (Vint 3) );
  assert (eval_match  (Vconstructor("Some", [Vint 1]))
                     [ Pconstructor("Some", None)     , Vint 666
                     ; Pconstructor("Some", Some Pany), Vint 777
                     ]
         = Some (Vint 777) );
  ()

let () = test_eval_match ()
(* let eval_lambda (l: Lambda.lambda) =      *)
(* type right_expr = int *)
(* type match_expr = Pexp_match of (string list * (pat * right_expr) list) *)

(* type token = Id | Add | Mul *)

(* module Show_token_explicit: (SHOW with type t = token) = struct *)
(*   type t = token *)
(*   let show = function *)
(*     | Id -> "Id" *)
(*     | Add -> "Add" *)
(*     | Mul -> "Mul" *)
(* end *)
(* implicit module Show_token = Show_token_explicit *)

(* type expr  = I | A of expr logic * expr logic | M of expr logic * expr logic *)
(* module rec Show_expr_explicit: (SHOW with type t = expr) = struct *)
(*   type t = expr *)
(*   let show = function *)
(*     | I -> "I" *)
(*     | A (l,r) -> *)
(*        sprintf "A (%s, %s)" (Show_expr_logic.show l) (Show_expr_logic.show r) *)
(*     | M (l,r) -> *)
(*        sprintf "M (%s, %s)" (Show_expr_logic.show l) (Show_expr_logic.show r) *)
(* end *)
(* and Show_expr_logic: (SHOW with type t = expr logic) = Show_logic_explicit(Show_expr_explicit) *)
(* implicit module Show_expr = Show_expr_explicit *)

(* open Tester.M *)

(* let (!) = embed *)

(* let sym t i i' = *)
(*   fresh (x xs) *)
(*     (i === x%xs) (t === x) (i' === xs) *)

(* let eof i = i === !(Nil : token llist) *)

(* let (|>) x y = fun i i'' r'' -> *)
(*   fresh (i' r') *)
(*     (x i  i' r') *)
(*     (y r' i' i'' r'') *)

(* let (<|>) x y = fun i i' r -> *)
(*   conde [x i i' r; y i i' r] *)

(* let rec pId i i' r = (sym !Id i i') &&& (r === !I) *)
(* and pAdd i i' r = (pMulPlusAdd <|> pMul) i i' r *)
(* and pMulPlusAdd i i' r = ( *)
(*       pMul |> *)
(*       (fun r i i'' r'' -> *)
(*          fresh (r' i') *)
(*            (sym !Add i i') *)
(*            (r'' === !(A (r, r'))) *)
(*            (pAdd i' i'' r') *)
(*       )) i i' r *)
(* and pMul i i' r = (pIdAstMul <|> pId) i i' r *)
(* and pIdAstMul i i' r= ( *)
(*       pId |> *)
(*       (fun r i i'' r'' -> *)
(*          fresh (r' i') *)
(*            (sym !Mul i i') *)
(*            (r'' === !(M (r, r'))) *)
(*            (pMul i' i'' r') *)
(*       )) i i' r *)
(* and pTop i i' r = pAdd i i' r *)

(* let pExpr i r = fresh (i') (pTop i i' r) (eof i') *)

(* open Tester *)

(* let _ = *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id])                   ) ); *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id; Mul; Id])          ) ); *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id; Mul; Id; Mul; Id]) ) ); *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id; Mul; Id; Add; Id]) ) ); *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id; Add; Id; Mul; Id]) ) ); *)
(*   run1 ~n:1 (REPR(pExpr (of_list [Id; Add; Id; Add; Id]) ) ); *)
(*   run1 ~n:1 (REPR(fun q -> pExpr q !(M (!I, !I))         ) ); *)
(*   () *)