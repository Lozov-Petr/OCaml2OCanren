(* Print all fully qualified names in expressions *)
open Printf
open Asttypes
open Longident
open Typedtree
open Ast_helper
open Tast_mapper

let () = Printexc.record_backtrace true

module Lozov = struct
open Typedtree
open Ident
open Asttypes
open Lexing
open Location
open Parsetree

(*****************************************************************************************************************************)

let fresh_var_prefix    = "q"
let tabling_attr_name   = "tabled"

let fresh_module_name   = "Fresh"
let fresh_one_name      = "one"
let fresh_two_name      = "two"
let fresh_three_name    = "three"
let fresh_four_name     = "four"
let fresh_five_name     = "five"
let fresh_succ_name     = "succ"

(*****************************************************************************************************************************)

let packages = ["MiniKanren"; "MiniKanrenStd"]

(*****************************************************************************************************************************)

type error = NotYetSupported of string
exception Error of error

let report_error fmt  = function
| NotYetSupported s -> Format.fprintf fmt "Not supported during relational conversion: %s\n%!" s

let fail_loc loc fmt =
  let b = Buffer.create 100 in
  let f = Format.formatter_of_buffer b in
  let () = Format.fprintf f fmt in
  let () = Location.print f loc in
  Format.pp_print_flush f ();
  failwith (Buffer.contents b)

(*****************************************************************************************************************************)

let get_max_index tast =

  let max_index = ref 0 in

  let set_max_index_from_name name =
    let prefix_length = String.length fresh_var_prefix in
    let length = String.length name in
    if length > prefix_length && (String.sub name 0 prefix_length) = fresh_var_prefix then
      let index = try String.sub name prefix_length (length - prefix_length) |> int_of_string with Failure _ -> -1
      in if index > !max_index then max_index := index in

  let expr sub x =
    match x.exp_desc with
    | Texp_ident (path, _, _) -> Path.name path |> set_max_index_from_name; x
    | _                       -> Tast_mapper.default.expr sub x in

  let finder = {Tast_mapper.default with expr} in

  finder.structure finder tast |> ignore; !max_index

(*****************************************************************************************************************************)

let untyper = Untypeast.default_mapper

let create_id  s = Lident s |> mknoloc |> Exp.ident
let create_pat s = mknoloc s |> Pat.var

let rec lowercase_lident = function
  | Lident s      -> Lident (Util.mangle_construct_name s)
  | Lapply (l, r) -> Lapply (lowercase_lident l, lowercase_lident r)
  | Ldot (t, s)   -> Ldot (lowercase_lident t, s)

let rec is_primary_type (t : Types.type_expr) =
  match t.desc with
  | Tarrow _ -> false
  | Tlink t' -> is_primary_type t'
  | _        -> true


let get_pat_name p =
  match p.pat_desc with
  | Tpat_var (name, _) -> name.name
  | _                  -> fail_loc p.pat_loc "Incorrect pattern"


let create_apply f = function
| []   -> f
| args ->
  let args = List.map (fun a -> Nolabel, a) args in
  match f.pexp_desc with
  | Pexp_apply (g, args') -> Exp.apply g (args' @ args)
  | _                     -> Exp.apply f args


let create_apply_to_list f arg_list =
  let new_arg = List.fold_right (fun x acc -> [%expr [%e x] :: [%e acc]]) arg_list [%expr []] in
  create_apply f [new_arg]


let create_conj = function
| []     -> failwith "Conjunction needs one or more arguments"
| [x]    -> x
| [x; y] -> [%expr [%e x] &&& [%e y]]
| l      -> create_apply_to_list [%expr (?&)] l


let create_disj = function
| []     -> failwith "Conjunction needs one or more arguments"
| [x]    -> x
| [x; y] -> [%expr [%e x] ||| [%e y]]
| l      -> create_apply_to_list [%expr conde] l


let create_fun var body =
  [%expr fun [%p create_pat var] -> [%e body]]


let create_fresh var body =
  create_apply [%expr call_fresh] [create_fun var body]


let create_inj expr = [%expr !! [%e expr]]


let filter_vars vars1 vars2 =
  List.filter (fun v -> List.for_all ((<>) v) vars2) vars1

(*****************************************************************************************************************************)

let translate tast start_index need_lowercase =

let lowercase_lident x =
  if need_lowercase
  then lowercase_lident x
  else x in

let curr_index = ref start_index in

let create_fresh_var_name () =
  let name = Printf.sprintf "%s%d" fresh_var_prefix !curr_index in
  incr curr_index;
  name in

let rec create_fresh_argument_names_by_type (typ : Types.type_expr) =
  match typ.desc with
  | Tarrow (_, _, right_typ, _) -> create_fresh_var_name () :: create_fresh_argument_names_by_type right_typ
  | Tlink typ                   -> create_fresh_argument_names_by_type typ
  | _                           -> [create_fresh_var_name ()] in

  (*************************************************)

  let rec unnest_expr let_vars expr =
    match expr.exp_desc with
    | Texp_ident (_, { txt = Longident.Lident name }, _) when List.for_all ((<>) name) let_vars -> untyper.expr untyper expr, []
    | Texp_constant c -> create_inj (Exp.constant (Untypeast.constant c)), []
    | Texp_construct ({txt = Lident s}, _, []) when s = "true" || s = "false" -> create_inj (untyper.expr untyper expr), []
    | Texp_tuple [a; b] ->
      let new_args, fv = List.map (unnest_expr let_vars) [a; b] |> List.split in
      let fv           = List.concat fv in
      create_apply [%expr pair] new_args, fv

    | Texp_construct (name, _, args) ->
      let new_args, fv = List.map (unnest_expr let_vars) args |> List.split in
      let fv           = List.concat fv in

      let new_args     = match new_args with
                         | [] -> [[%expr ()]]
                         | l  -> l in

      let new_name     = match name.txt with
                         | Lident "[]" -> Lident "nil"
                         | Lident "::" -> Lident "%"
                         | txt         -> lowercase_lident txt in

      create_apply (Exp.ident (mknoloc new_name)) new_args, fv

    | _ when is_primary_type expr.exp_type ->
      let fr_var = create_fresh_var_name () in
      create_id fr_var, [(fr_var, expr)]
    | _ -> translate_expression let_vars expr, []


  and translate_construct let_vars expr =
    let constr, binds = unnest_expr let_vars expr in
    let out_var_name  = create_fresh_var_name () in
    let unify_constr  = [%expr [%e create_id out_var_name] === [%e constr]] in
    let conjs         = unify_constr :: List.map (fun (v,e) -> create_apply (translate_expression let_vars e) [create_id v]) binds in
    let conj          = create_conj conjs in
    let with_fresh    = List.fold_right create_fresh (List.map fst binds) conj in
    create_fun out_var_name with_fresh


  and translate_ident let_vars name typ =
    if is_primary_type typ && List.for_all ((<>) name) let_vars
      then let var = create_fresh_var_name () in
           [%expr fun [%p create_pat var] -> [%e create_id name] === [%e create_id var]]
      else create_id name


  and translate_abstraciton let_vars case =
    let let_vars = filter_vars let_vars [get_pat_name case.c_lhs] in
    Exp.fun_ Nolabel None (untyper.pat untyper case.c_lhs) (translate_expression let_vars case.c_rhs)


  and normalize_apply expr =
    match expr.exp_desc with
    | Texp_apply (f, args_r) ->
      let expr', args_l = normalize_apply f in
      expr', args_l @ List.map (function | (_, Some x) -> x | _ -> fail_loc expr.exp_loc "Incorrect argument") args_r
    | _ -> expr, []


  and translate_apply let_vars expr =
    let f, args = normalize_apply expr in
    let new_args, binds = List.map (unnest_expr let_vars) args |> List.split in
    let binds = List.concat binds in
    if List.length binds = 0
      then create_apply (translate_expression let_vars f) new_args
      else let eta_vars   = create_fresh_argument_names_by_type expr.exp_type in
           let eta_call   = create_apply (translate_expression let_vars f) (new_args @ List.map create_id eta_vars) in
           let conjs      = List.map (fun (v,e) -> create_apply (translate_expression let_vars e) [create_id v]) binds @ [eta_call] in
           let full_conj  = create_conj conjs in
           let with_fresh = List.fold_right create_fresh (List.map fst binds) full_conj in
           List.fold_right create_fun eta_vars with_fresh


  and translate_nonrec_let let_vars bind expr =
    let new_let_vars =
      if is_primary_type bind.vb_expr.exp_type
      then get_pat_name bind.vb_pat :: let_vars
      else let_vars in

     Exp.let_ Nonrecursive [Vb.mk (untyper.pat untyper bind.vb_pat) (translate_expression let_vars bind.vb_expr)] (translate_expression new_let_vars expr)


  and translate_rec_let let_vars bind expr =
    let rec is_func_type (t : Types.type_expr) =
      match t.desc with
      | Tarrow _ -> true
      | Tlink t' -> is_func_type t'
      | _        -> false in

    let rec has_func_arg (t : Types.type_expr) =
      match t.desc with
      | Tarrow (_,f,s,_) -> is_func_type f || has_func_arg s
      | Tlink t'         -> has_func_arg t'
      | _                -> false in

    let rec get_tabling_rank (typ : Types.type_expr) =
      match typ.desc with
      | Tarrow (_, _, right_typ, _) -> create_apply [%expr Tabling.succ] [get_tabling_rank right_typ]
      | Tlink typ                   -> get_tabling_rank typ
      | _                           -> [%expr Tabling.one] in

    let body = translate_expression let_vars bind.vb_expr in
    let expr = translate_expression let_vars expr in
    let typ  = bind.vb_expr.exp_type in

    let has_tabled_attr = List.exists (fun a -> (fst a).txt = tabling_attr_name) bind.vb_attributes in

    if not has_tabled_attr
    then Exp.let_ Recursive [Vb.mk (untyper.pat untyper bind.vb_pat) body] expr
    else if has_func_arg typ
         then fail_loc bind.vb_loc "Tabled function has functional argument"
         else let name = get_pat_name bind.vb_pat in
              let abst = create_fun name body in
              let rank = get_tabling_rank typ in
              let appl = create_apply [%expr Tabling.tabledrec] [rank; abst] in
              Exp.let_ Nonrecursive [Vb.mk (untyper.pat untyper bind.vb_pat) appl] expr

  and translate_let let_vars flag bind expr =
    match flag with
    | Recursive    -> translate_rec_let    let_vars bind expr
    | Nonrecursive -> translate_nonrec_let let_vars bind expr


  and translate_match let_vars expr cases typ =
    let args = create_fresh_argument_names_by_type typ in

    let scrutinee_is_var =
      match expr.exp_desc with
      | Texp_ident _ -> true
      | _            -> false in

    let scrutinee_var =
      match expr.exp_desc with
      | Texp_ident (_, { txt = Longident.Lident name }, _) -> name
      | Texp_ident _                                       -> fail_loc expr.exp_loc "Incorrect variable"
      | _                                                  -> create_fresh_var_name () in

    let rec translate_pat pat =
      match pat.pat_desc with
      | Tpat_any                                       -> let var = create_fresh_var_name () in create_id var, [var]
      | Tpat_var (v, _)                                -> create_id v.name, [v.name]
      | Tpat_constant c                                -> Untypeast.constant c |> Exp.constant |> create_inj, []
      | Tpat_construct ({txt = Lident "true"},  _, []) -> [%expr !!true],  []
      | Tpat_construct ({txt = Lident "false"}, _, []) -> [%expr !!false], []
      | Tpat_construct ({txt = Lident "[]"},    _, []) -> [%expr nil ()],  []
      | Tpat_construct (id              ,       _, []) -> [%expr [%e lowercase_lident id.txt |> mknoloc |> Exp.ident] ()], []
      | Tpat_construct ({txt}, _, args)                ->
        let args, vars = List.map translate_pat args |> List.split in
        let vars = List.concat vars in
        let constr =
          match txt with
          | Lident "::" -> [%expr (%)]
          | _           -> lowercase_lident txt |> mknoloc |> Exp.ident in
        create_apply constr args, vars
      | Tpat_tuple [l; r] ->
        let args, vars = List.map translate_pat [l; r] |> List.split in
        let vars = List.concat vars in
        create_apply [%expr pair] args, vars
      | _ -> fail_loc pat.pat_loc "Incorrect pattern in pattern matching" in

    let rec rename var1 var2 pat =
      match pat.pexp_desc with
      | Pexp_ident { txt = Lident name } -> if name = var1 then create_id var2 else pat
      | Pexp_apply (f, args) -> List.map snd args |> List.map (rename var1 var2) |> create_apply f
      | _ -> pat in

    let translate_case case =
      let pat, vars  = translate_pat case.c_lhs in

      let is_overlap = List.exists ((=) scrutinee_var) vars in
      let new_var    = if is_overlap then create_fresh_var_name () else "" in
      let pat        = if is_overlap then rename scrutinee_var new_var pat else pat in
      let vars       = if is_overlap then List.map (fun n -> if n = scrutinee_var then new_var else n) vars else vars in


      let unify      = [%expr [%e create_id scrutinee_var] === [%e pat]] in
      let body       = create_apply (translate_expression (filter_vars let_vars vars) case.c_rhs) (List.map create_id args) in
      let body       = if is_overlap then create_apply (create_fun scrutinee_var body) [create_id new_var] else body in
      let conj       = create_conj [unify; body] in
      List.fold_right create_fresh vars conj in

    let new_cases  = List.map translate_case cases in
    let disj       = create_disj new_cases in
    let with_fresh = if scrutinee_is_var
                     then disj
                     else create_conj [create_apply (translate_expression let_vars expr) [create_id scrutinee_var]; disj]
                       |> create_fresh scrutinee_var in

    List.fold_right create_fun args with_fresh


  and translate_bool_funs is_or =
    let a1  = create_fresh_var_name () in
    let a2  = create_fresh_var_name () in
    let q   = create_fresh_var_name () in
    let fst = if is_or then [%expr !!true]  else [%expr !!false] in
    let snd = if is_or then [%expr !!false] else [%expr !!true]  in
    [%expr fun [%p create_pat a1] [%p create_pat a2] [%p create_pat q] ->
             conde [([%e create_id a1] === [%e fst]) &&& ([%e create_id q] === [%e fst]);
                    ([%e create_id a1] === [%e snd]) &&& ([%e create_id q] === [%e create_id a2])]]


  and translate_eq_funs is_eq =
    let a1  = create_fresh_var_name () in
    let a2  = create_fresh_var_name () in
    let q   = create_fresh_var_name () in
    let fst = if is_eq then [%expr !!true]  else [%expr !!false] in
    let snd = if is_eq then [%expr !!false] else [%expr !!true]  in
    [%expr fun [%p create_pat a1] [%p create_pat a2] [%p create_pat q] ->
             conde [([%e create_id a1] === [%e create_id a2]) &&& ([%e create_id q] === [%e fst]);
                    ([%e create_id a1] =/= [%e create_id a2]) &&& ([%e create_id q] === [%e snd])]]


  and translate_not_fun () =
    let a  = create_fresh_var_name () in
    let q  = create_fresh_var_name () in
    [%expr fun [%p create_pat a] [%p create_pat q] ->
             conde [([%e create_id a] === !!true ) &&& ([%e create_id q] === !!false);
                    ([%e create_id a] === !!false) &&& ([%e create_id q] === !!true )]]


  and translaet_if let_vars cond th el typ =
  let args = create_fresh_argument_names_by_type typ in

  let cond_is_var =
    match cond.exp_desc with
    | Texp_ident _ -> true
    | _            -> false in

  let cond_var =
    match cond.exp_desc with
    | Texp_ident (_, { txt = Longident.Lident name }, _) -> name
    | Texp_ident _                                       -> fail_loc cond.exp_loc "Incorrect variable"
    | _                                                  -> create_fresh_var_name () in

  let th = create_apply (translate_expression let_vars th) (List.map create_id args) in
  let el = create_apply (translate_expression let_vars el) (List.map create_id args) in

  let body = [%expr conde [([%e create_id cond_var] === !!true ) &&& [%e th];
                           ([%e create_id cond_var] === !!false) &&& [%e el]]]
  in

  let with_fresh =
    if cond_is_var then body
    else [%expr call_fresh (fun [%p create_pat cond_var] -> ([%e translate_expression let_vars cond] [%e create_id cond_var]) &&& [%e body])] in

    List.fold_right create_fun args with_fresh

  and translate_expression let_vars expr =
    match expr.exp_desc with
    | Texp_constant _          -> translate_construct let_vars expr
    | Texp_construct _         -> translate_construct let_vars expr

    | Texp_tuple [l; r]        -> translate_construct let_vars expr

    | Texp_apply _             -> translate_apply let_vars expr

    | Texp_match (e, cs, _, _) -> translate_match let_vars e cs expr.exp_type

    | Texp_ifthenelse (cond, th, Some el) -> translaet_if let_vars cond th el expr.exp_type

    | Texp_function {cases = [case]} -> translate_abstraciton let_vars case

    | Texp_ident (_, { txt = Lident "="  }, _)  -> translate_eq_funs true
    | Texp_ident (_, { txt = Lident "<>" }, _)  -> translate_eq_funs false

    | Texp_ident (_, { txt = Lident "||" }, _)  -> translate_bool_funs true
    | Texp_ident (_, { txt = Lident "&&" }, _)  -> translate_bool_funs false

    | Texp_ident (_, { txt = Lident "not" }, _) -> translate_not_fun ()

    | Texp_ident (_, { txt = Lident name }, _) -> translate_ident let_vars name expr.exp_type

    | Texp_let (flag, [bind], expr) -> translate_let let_vars flag bind expr

    | Texp_let _ -> fail_loc expr.exp_loc "Operator LET ... AND isn't supported" (*TODO support LET ... AND*)
    | _ -> fail_loc expr.exp_loc "Incorrect expression"
  in

  let translate_external_value_binding let_vars vb =
    let pat  = untyper.pat untyper vb.vb_pat in
    let expr = translate_expression let_vars vb.vb_expr in
    Vb.mk pat expr in


  let mark_type_declaration td =
      match td.typ_kind with
      | Ttype_variant cds -> { td with typ_attributes = [(mknoloc "put_distrib_here", Parsetree.PStr [])] }
      | _                 -> fail_loc td.typ_loc "Incrorrect type declaration" in


  let translate_structure_item let_vars stri =
    match stri.str_desc with
    | Tstr_value (rec_flag, [bind]) ->
        Str.value rec_flag [translate_external_value_binding let_vars bind]
    | Tstr_type (rec_flag, decls) ->
      let new_decls = List.map mark_type_declaration decls in
      untyper.structure_item untyper { stri with str_desc = Tstr_type (rec_flag, new_decls) }
    | _ -> fail_loc stri.str_loc "Incorrect structure item" in


  let translate_structure str =
    let rec translate_items let_vars = function
    | []    -> []
    | x::xs ->
      let new_let_vars =
        match x.str_desc with
        | Tstr_value (Nonrecursive, [{vb_expr; vb_pat = {pat_desc = Tpat_var (var, _)}}]) when is_primary_type vb_expr.exp_type -> var.name :: let_vars
        | _                                                                                                                     -> let_vars in
      translate_structure_item let_vars x :: translate_items new_let_vars xs in

    translate_items [] str.str_items in


  translate_structure tast

(*****************************************************************************************************************************)

let add_packages ast =
  List.map (fun n -> Lident n |> mknoloc |> Opn.mk |> Str.open_) packages @ ast

(*****************************************************************************************************************************)

let beta_reductor minimal_index =

  let need_subst name arg =
    let arg_is_var =
      match arg.pexp_desc with
      | Pexp_ident _ -> true
      | _            -> false in

    let prefix_length = String.length fresh_var_prefix in
    let length        = String.length name in

    let index = if length > prefix_length && (String.sub name 0 prefix_length) = fresh_var_prefix
                then try String.sub name prefix_length (length - prefix_length) |> int_of_string
                     with Failure _ -> -1
                else -1 in

    index >= minimal_index || arg_is_var in

  let name_from_pat pat =
    match pat.ppat_desc with
    | Ppat_var loc -> loc.txt
    | _            -> fail_loc pat.ppat_loc "Incorrect pattern in beta reduction" in

  let rec substitute expr var subst =
    match expr.pexp_desc with
    | Pexp_ident {txt = Lident name} -> if name = var then subst else expr
    | Pexp_fun (_, _, pat, body) ->
      let name = name_from_pat pat in
      if name = var then expr else substitute body var subst |> create_fun name
    | Pexp_apply (func, args) ->
      List.map snd args |>
      List.map (fun a -> substitute a var subst) |>
      create_apply (substitute func var subst)
    | Pexp_let (flag, vbs, expr) ->
      let is_rec       = flag = Recursive in
      let var_in_binds = List.map (fun vb -> name_from_pat vb.pvb_pat) vbs |> List.exists ((=) var) in

      let subst_in_bind bind =
        if is_rec && var_in_binds || not is_rec && var = (name_from_pat bind.pvb_pat)
        then bind
        else { bind with pvb_expr = substitute bind.pvb_expr var subst } in

      let new_vbs = List.map subst_in_bind vbs in
      Exp.let_ flag new_vbs (if var_in_binds then expr else substitute expr var subst)

    | Pexp_construct (name, Some expr) -> Some (substitute expr var subst) |> Exp.construct name
    | Pexp_tuple exprs -> List.map (fun e -> substitute e var subst) exprs |> Exp.tuple
    | _ -> expr in


  let rec beta_reduction expr args =
    match expr.pexp_desc with
    | Pexp_apply (func, args') ->
      let old_args = List.map snd args' in
      let new_args = List.map (fun a -> beta_reduction a []) old_args in
      List.append new_args args |> beta_reduction func

    | Pexp_fun (_, _, pat, body) ->
      let var = match pat.ppat_desc with
                | Ppat_var v -> v.txt
                | _          -> fail_loc pat.ppat_loc "Incorrect arg name in beta reduction" in
      begin match args with
        | arg::args' when need_subst var arg -> beta_reduction (substitute body var arg) args'
        | _                                  -> create_apply (beta_reduction body [] |> create_fun var) args
      end
    | Pexp_let (flag, vbs, expr) ->
      let new_vbs  = List.map (fun v -> { v with pvb_expr = beta_reduction v.pvb_expr [] }) vbs in
      let new_expr = beta_reduction expr args in
      Exp.let_ flag  new_vbs new_expr

    | Pexp_construct (name, Some expr) -> Some (beta_reduction expr []) |> Exp.construct name
    | Pexp_tuple args -> List.map (fun a -> beta_reduction a []) args |> Exp.tuple
    | _ -> create_apply expr args in

  let expr _ x = beta_reduction x [] in
  { Ast_mapper.default_mapper with expr }

(*****************************************************************************************************************************)

let fresh_var_upper =

  let rec get_conds_and_vars expr =
    match expr.pexp_desc with
    | Pexp_apply ({pexp_desc = Pexp_ident {txt = Lident "call_fresh"}},
                  [_, {pexp_desc = Pexp_fun (_, _, {ppat_desc = Ppat_var {txt}}, body)}]) ->
      let conds, vars = get_conds_and_vars body in
      conds, txt :: vars

    | Pexp_apply ({pexp_desc = Pexp_ident {txt = Lident "&&&"}}, [_, a; _, b]) ->
      let conds, vars = List.map get_conds_and_vars [a; b] |> List.split in
      List.concat conds, List.concat vars

    | Pexp_apply ({pexp_desc = Pexp_ident {txt = Lident "?&"}}, [_, args]) ->
      let rec get_args_from_list args =
        match args.pexp_desc with
        | Pexp_construct ({txt = Lident "[]"}, _)                                     -> []
        | Pexp_construct ({txt = Lident "::"}, Some {pexp_desc = Pexp_tuple [hd;tl]}) -> hd :: get_args_from_list tl
        | _                                                                           -> fail_loc args.pexp_loc "Bad args in fresh var upper" in

      let args = get_args_from_list args in
      let conds, vars = List.map get_conds_and_vars args |> List.split in
      List.concat conds, List.concat vars

    | _ -> [expr], [] in

    let upper sub expr =
      let conds, vars = get_conds_and_vars expr in
      let new_conds   = List.map (Ast_mapper.default_mapper.expr sub) conds in

      let vars_as_apply = function
        | x::xs -> create_apply (create_id x) (List.map create_id xs)
        | _     -> failwith "Incorrect variable count" in

      let vars_arg = function
        | [v] -> Exp.tuple [create_id v]
        | _   -> vars_as_apply vars in

      if List.length vars > 0
      then create_apply [%expr fresh] (vars_arg vars :: new_conds)
      else create_conj new_conds in

    { Ast_mapper.default_mapper with expr = upper }

(*****************************************************************************************************************************)

end


let print_if ppf flag printer arg =
  if !flag then Format.fprintf ppf "%a@." printer arg;
  arg

let eval_if_need flag f =
  if flag then f else fun x -> x

let only_generate ~oldstyle hook_info tast =
  if oldstyle
  then try
    let open Lozov  in
    let need_reduce     = true in
    let need_lower_case = true in
    let need_normalize  = true in
    let start_index = get_max_index tast in
    let reductor    = beta_reductor start_index in
    translate tast start_index need_lower_case |>
    add_packages |>
    eval_if_need need_reduce    (reductor.structure reductor) |>
    eval_if_need need_normalize (fresh_var_upper.structure fresh_var_upper) |>
    PutDistrib.process |>
    print_if Format.std_formatter Clflags.dump_parsetree Printast.implementation |>
    print_if Format.std_formatter Clflags.dump_source Pprintast.structure
  with
    | Lozov.Error e as exc ->
      Lozov.report_error Format.std_formatter e;
      raise exc
  else
  try
    print_endline "new style";
    let reduced_ast = Smart_mapper.process tast in
    reduced_ast |>
    (*PutDistrib.process |>*)
    print_if Format.std_formatter Clflags.dump_parsetree Printast.implementation |>
    print_if Format.std_formatter Clflags.dump_source Pprintast.structure
  with exc ->
    Printexc.print_backtrace stdout;
    raise exc


let main = fun (hook_info : Misc.hook_info) ((tast, coercion) : Typedtree.structure * Typedtree.module_coercion) ->
  let new_ast       = only_generate ~oldstyle:false hook_info tast in

  try
  (*        let new_ast = [] in*)
    let old = ref (!Clflags.print_types) in
    Clflags.print_types := true;
    let (retyped_ast, new_sig, _env) =
      let () = print_endline "retyping generated code" in
      Printexc.print
      (Typemod.type_structure (Compmisc.initial_env()) new_ast)
      Location.none
    in
    Clflags.print_types := !old;
  (*        Printtyped.implementation_with_coercion Format.std_formatter (retyped_ast, coercion);*)
    Printtyp.wrap_printing_env (Compmisc.initial_env()) (fun () ->
      let open Format in
      fprintf std_formatter "%a@."
        Printtyp.signature (Typemod.simplify_signature new_sig));
    (retyped_ast, Tcoerce_none)
  with
    | Lozov.Error e as exc ->
      Lozov.report_error Format.std_formatter e;
      raise exc
(*    | Error e as exc ->
      report_error Format.std_formatter e;
      raise exc*)
    | Env.Error e as exc ->
      Env.report_error Format.std_formatter e;
      Format.printf "\n%!";
      raise exc
    | Typecore.Error (_loc,_env,e) as exc ->
      Typecore.report_error _env Format.std_formatter e;
      Format.printf "\n%!";
      raise exc
    | Typemod.Error (_loc,_env,e) as exc ->
      Typemod.report_error _env Format.std_formatter e;
      Format.printf "\n%!";
      raise exc
    | Typetexp.Error (_loc,_env,e) as exc ->
      Typetexp.report_error _env Format.std_formatter e;
      Format.printf "\n%!";
      raise exc
    | Typemod.Error_forward e as exc ->
      raise exc

(*
(* registering actual translator *)
let () = Typemod.ImplementationHooks.add_hook "ml_to_mk" main
*)
