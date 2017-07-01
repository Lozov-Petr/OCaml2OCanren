open Longident
open Location
open Asttypes
open Parsetree
open Ast_helper
open Ast_convenience

let deriver = "showT"
let raise_errorf = Ppx_deriving.raise_errorf

type options = { with_path : bool }

let parse_options options =
  let with_path = ref true in
  options |> List.iter (fun (name, expr) ->
    match name with
    | "with_path" -> with_path := Ppx_deriving.Arg.(get_expr ~deriver bool) expr
    | _ -> raise_errorf ~loc:expr.pexp_loc "%s does not support option %s" deriver name);
  { with_path = !with_path }

let attr_nobuiltin attrs =
  Ppx_deriving.(attrs |> attr ~deriver "nobuiltin" |> Arg.get_flag ~deriver)

let attr_printer attrs =
  Ppx_deriving.(attrs |> attr ~deriver "printer" |> Arg.(get_attr ~deriver expr))

let attr_polyprinter attrs =
  Ppx_deriving.(attrs |> attr ~deriver "polyprinter" |> Arg.(get_attr ~deriver expr))

let attr_opaque attrs =
  Ppx_deriving.(attrs |> attr ~deriver "opaque" |> Arg.get_flag ~deriver)

let argn = Printf.sprintf "a%d"
let argl = Printf.sprintf "a%s"

let pattn typs   = List.mapi (fun i _ -> pvar (argn i)) typs
let pattl labels = List.map (fun { pld_name = { txt = n } } -> n, pvar (argl n)) labels

let pconstrrec name fields = pconstr name [precord ~closed:Closed fields]

let wrap_printer quoter printer =
  Ppx_deriving.quote quoter
    [%expr (let fprintf = Format.fprintf in [%e printer]) [@ocaml.warning "-26"]]

let pp_type_of_decl ~options ~path type_decl =
  let _ = parse_options options in
  let typ = Ppx_deriving.core_type_of_type_decl type_decl in
  Ppx_deriving.poly_arrow_of_type_decl
    (fun var -> [%type: Format.formatter -> [%t var] -> Ppx_deriving_runtime.unit])
    type_decl
    [%type: Format.formatter -> [%t typ] -> Ppx_deriving_runtime.unit]

let show_type_of_decl ~options ~path type_decl =
  let _ = parse_options options in
  let typ = Ppx_deriving.core_type_of_type_decl type_decl in
  Ppx_deriving.poly_arrow_of_type_decl
    (fun var -> [%type: Format.formatter -> [%t var] -> Ppx_deriving_runtime.unit])
    type_decl
    [%type: [%t typ] -> Ppx_deriving_runtime.string]

let sig_of_type ~options ~path type_decl =
  let _ = parse_options options in
  [Sig.value (Val.mk (mknoloc (Ppx_deriving.mangle_type_decl (`Prefix "pppt") type_decl))
              (pp_type_of_decl ~options ~path type_decl));
   Sig.value (Val.mk (mknoloc (Ppx_deriving.mangle_type_decl (`Prefix "show") type_decl))
              (show_type_of_decl ~options ~path type_decl))]

let thrd3 (_,_,x) = x


let migrate =
  let open Migrate_parsetree in
  Versions.migrate (module OCaml_405) (module OCaml_current)

let string_of_expression e =
  Format.set_margin 1000;
  let open Migrate_parsetree in
  let ans = Format.asprintf "%a" Pprintast.expression (migrate.Versions.copy_expression e) in
  Format.set_margin 80;
  ans

let string_of_core_type e =
  Format.set_margin 1000;
  let open Migrate_parsetree in
  let ans = Format.asprintf "%a" Pprintast.core_type (migrate.Versions.copy_core_type e) in
  Format.set_margin 80;
  ans

let rec expr_of_typ quoter typ =
  (* Format.printf "expr_of_typ: typ = %s\n%!" (string_of_core_type typ); *)
  let expr_of_typ = expr_of_typ quoter in
  match attr_printer typ.ptyp_attributes with
  | Some printer ->
      failwith "not supported"
      [%expr [%e wrap_printer quoter printer] fmt]
  | None ->
  if false (*attr_opaque typ.ptyp_attributes*) then
    0, [%expr "opaque"], [%expr fun _ -> Format.pp_print_string fmt "<opaque>"]
  else
    let format x = [%expr Format.fprintf fmt [%e str x]] in
    let seq start finish fold typ =
      [%expr fun x ->
        Format.fprintf fmt [%e str start];
        ignore ([%e fold] (fun sep x ->
          if sep then Format.fprintf fmt ";@ ";
          [%e thrd3 @@ expr_of_typ typ] x; true) false x);
        Format.fprintf fmt [%e str finish];]
    in
    (* TODO: fix remove_pervasives in ppx_deriving lib *)
    (* let typ = Ppx_deriving.remove_pervasives ~deriver typ in *)
    (* Format.printf "after remove_pervasives: typ = %s\n%!" (string_of_core_type typ); *)

    match typ with
    | [%type: _] -> 0, [%expr "???"], [%expr fun _ -> Format.pp_print_string fmt "_"]
    | { ptyp_desc = Ptyp_arrow _ } ->
      0, [%expr "???"], [%expr fun _ -> Format.pp_print_string fmt "<fun>"]
    | { ptyp_desc = Ptyp_alias (base_typ,name)} ->
        let (_,_,basse) = expr_of_typ base_typ in

        0,[%expr "???"],
        [%expr
          (* TODO: repalce typ__a in printed type *)
          let typ__b = [%e Exp.constant (Pconst_string (string_of_core_type base_typ,None)) ] in
          (* let rec poly_b typ__b = pppt_glist typ__a poly_a typ__b poly_b in *)
          let rec poly_b typ__b fmt = [%e basse ] in
          [%e thrd3 @@ expr_of_typ base_typ ]
        ]

    | { ptyp_desc = Ptyp_constr _ } ->
      let builtin = not (attr_nobuiltin typ.ptyp_attributes) in
      begin match builtin, typ with
      | true, [%type: unit]        -> 0, [%expr "unit"], [%expr fun () -> Format.pp_print_string fmt "()"]
      | true, [%type: int]         -> 0, [%expr "int"], format "%d"
      (* | true, [%type: int32]
      | true, [%type: Int32.t]     -> format "%ldl"
      | true, [%type: int64]
      | true, [%type: Int64.t]     -> format "%LdL"
      | true, [%type: nativeint]
      | true, [%type: Nativeint.t] -> format "%ndn"
      | true, [%type: float]       -> format "%F"
      | true, [%type: bool]        -> format "%B"
      | true, [%type: char]        -> format "%C" *)
      | true, [%type: string]
      | true, [%type: String.t]    -> 0, [%expr "string"], format "%S"
      (* | true, [%type: bytes]
      | true, [%type: Bytes.t] ->
        [%expr fun x -> Format.fprintf fmt "%S" (Bytes.to_string x)] *)
      (* | true, [%type: [%t? typ] ref] ->
        [%expr fun x ->
          Format.pp_print_string fmt "ref (";
          [%e expr_of_typ typ] !x;
          Format.pp_print_string fmt ")"] *)

      | true, [%type: [%t? typ] list]  ->
          let ans =
            let start = "@[<2>[" in
            let finish = "@,]@]" in
            let fold = [%expr List.fold_left] in
            [%expr fun x ->
              Format.fprintf fmt [%e str start];
              ignore ([%e fold] (fun sep x ->
                if sep then Format.fprintf fmt ";@ ";
                [%e thrd3 @@ expr_of_typ typ] x; true) false x);
              Format.fprintf fmt [%e str finish];]
          in

          0, [%expr "list"], ans
          (* seq "@[<2>["   "@,]@]" [%expr List.fold_left]  typ *)
      (* | true, [%type: [%t? typ] array] -> seq "@[<2>[|" "@,|]@]" [%expr Array.fold_left] typ
      | true, [%type: [%t? typ] option] ->
        [%expr
          function
          | None -> Format.pp_print_string fmt "None"
          | Some x ->
            Format.pp_print_string fmt "(Some ";
            [%e expr_of_typ typ] x;
            Format.pp_print_string fmt ")"]
      | true, ([%type: ([%t? ok_t], [%t? err_t]) result] |
               [%type: ([%t? ok_t], [%t? err_t]) Result.result]) ->
        [%expr
          function
          | Result.Ok ok ->
            Format.pp_print_string fmt "(Ok ";
            [%e expr_of_typ ok_t] ok;
            Format.pp_print_string fmt ")"
          | Result.Error e ->
            Format.pp_print_string fmt "(Error ";
            [%e expr_of_typ err_t] e;
            Format.pp_print_string fmt ")"] *)
      (* | true, ([%type: [%t? typ] lazy_t] | [%type: [%t? typ] Lazy.t]) ->
        [%expr fun x ->
          if Lazy.is_val x then [%e expr_of_typ typ] (Lazy.force x)
          else Format.pp_print_string fmt "<not evaluated>"] *)
      | _, { ptyp_desc = Ptyp_constr ({ txt = lid }, args) } ->
        (* Format.printf "%s" (Longident.flatten lid |> String.concat " "); *)
        let args_pp = List.concat @@ List.map (fun typ ->
          let _,typ1,pp = expr_of_typ typ in
          let the_typ = match typ.ptyp_desc with
          | Ptyp_var name -> Pat.var @@ mknoloc ("typ__" ^ name)
          | _ -> Pat.any ()
          in
          (* [ typ; [%expr fun _ fmt -> [%e pp]] ] *)
          [ typ1; [%expr fun [%p the_typ ] fmt -> [%e pp]] ]
        ) args in
        let printer =
          match attr_polyprinter typ.ptyp_attributes with
          | Some printer -> wrap_printer quoter printer
          | None ->
            let printer = Exp.ident (mknoloc (Ppx_deriving.mangle_lid (`Prefix "pppt") lid)) in
            Ppx_deriving.quote quoter printer
        in
        0,[%expr ""], (app printer (args_pp @ [[%expr fmt]]))
      | _ -> assert false
      end
    | { ptyp_desc = Ptyp_tuple typs } ->
      let typs,funcs = List.split @@
        List.mapi (fun i typ -> match expr_of_typ typ with _,a,b -> (a,b)) typs
      in
      let the_big_typ =
        [%expr "asdfasdfas"]
      in
      let args = List.mapi (fun i foo -> app foo [evar (argn i)]) funcs in
      0, the_big_typ,
      [%expr
        fun [%p ptuple (List.mapi (fun i _ -> pvar (argn i)) typs)] ->
        Format.fprintf fmt "(@[";
        [%e args |> Ppx_deriving.(fold_exprs
                (seq_reduce ~sep:[%expr Format.fprintf fmt ",@ "]))];
        Format.fprintf fmt "@])"]
    (* | { ptyp_desc = Ptyp_variant (fields, _, _); ptyp_loc } ->
      let cases =
        fields |> List.map (fun field ->
          match field with
          | Rtag (label, _, true (*empty*), []) ->
            Exp.case (Pat.variant label None)
                     [%expr Format.pp_print_string fmt [%e str ("`" ^ label)]]
          | Rtag (label, _, false, [typ]) ->
            Exp.case (Pat.variant label (Some [%pat? x]))
                     [%expr Format.fprintf fmt [%e str ("`" ^ label ^ " (@[<hov>")];
                            [%e expr_of_typ typ] x;
                            Format.fprintf fmt "@])"]
          | Rinherit ({ ptyp_desc = Ptyp_constr (tname, _) } as typ) ->
            Exp.case [%pat? [%p Pat.type_ tname] as x]
                     [%expr [%e expr_of_typ typ] x]
          | _ ->
            raise_errorf ~loc:ptyp_loc "%s cannot be derived for %s"
                         deriver (Ppx_deriving.string_of_core_type typ))
      in
      Exp.function_ cases *)
    | { ptyp_desc = Ptyp_var name } ->
        (* Format.printf "just a var\n"; *)
        1,
        Exp.ident @@ lid ("typ__" ^ name),
        [%expr [%e evar ("poly_"^name)] [%e evar ("typ__"^name)] fmt]

    | { ptyp_loc } ->
      raise_errorf ~loc:ptyp_loc "%s cannot be derived for %s"
                   deriver (Ppx_deriving.string_of_core_type typ)

let str_of_type ~options ~path ({ ptype_loc = loc } as type_decl) =
  let show_opts = parse_options options in
  let quoter = Ppx_deriving.create_quoter () in
  let path = Ppx_deriving.path_of_type_decl ~path type_decl in
  let prettyprinter : expression =
    match type_decl.ptype_kind, type_decl.ptype_manifest with
    | Ptype_abstract, Some manifest ->
        (* Format.printf "A. manifest is %s\n%!" (string_of_core_type manifest); *)
        let (_arity,_,shower) = expr_of_typ quoter manifest in
        (* assert false; *)
      (* let ans =
        List.fold_right (fun (x,_) acc ->
            match x.ptyp_desc with
            | Ptyp_var s -> [%expr fun [%p Pat.var (mknoloc s)] -> [%e acc]]
            | _ -> assert false
          )
          type_decl.ptype_params
          shower
      in *)
      let ans = shower in
      [%expr fun fmt -> [%e ans]]
    | Ptype_variant constrs, _ ->
      (* Format.printf "B\n%!"; *)
      let cases =
        constrs |> List.map (fun { pcd_name = { txt = name' }; pcd_args; pcd_attributes } ->
          let constr_name =
            let path = if show_opts.with_path then path else [] in
            Ppx_deriving.expand_path ~path name'
          in

          match attr_printer pcd_attributes, pcd_args with
          | Some printer, Pcstr_tuple(args) ->
            let rec range from_idx to_idx =
              if from_idx = to_idx
              then []
              else from_idx::(range (from_idx+1) to_idx)
            in
            let indices = range 0 (List.length args) in
            let pattern_vars =
              List.map (fun i -> pvar ("a" ^ string_of_int i)) indices
            in
            let expr_vars =
              List.map (fun i -> evar ("a" ^ string_of_int i)) indices
            in
            Exp.case (pconstr name' pattern_vars)
              [%expr [%e wrap_printer quoter printer] fmt
                        [%e tuple expr_vars]]
          | Some printer, Pcstr_record(labels) ->
            let args = labels |> List.map (fun { pld_name = { txt = n } } -> evar (argl n)) in
            Exp.case (pconstrrec name' (pattl labels))
                     (app (wrap_printer quoter printer) ([%expr fmt] :: args))
          | None, Pcstr_tuple(typs) ->
            let args =
              List.mapi (fun i typ -> app (thrd3 @@ expr_of_typ quoter typ) [evar (argn i)]) typs in
            let printer =
              match args with
              | []   -> [%expr Format.pp_print_string fmt [%e str constr_name]]
              | [arg] ->
                [%expr
                  Format.fprintf fmt [%e str ("(@[<2>" ^  constr_name ^ "@ ")];
                  [%e arg];
                  Format.fprintf fmt "@])"]
              | args ->
                [%expr
                  Format.fprintf fmt [%e str ("(@[<2>" ^  constr_name ^ " (@,")];
                  [%e args |> Ppx_deriving.(fold_exprs
                        (seq_reduce ~sep:[%expr Format.fprintf fmt ",@ "]))];
                  Format.fprintf fmt "@,))@]"]
            in
            Exp.case (pconstr name' (pattn typs)) printer
          | None, Pcstr_record(labels) ->
            let args =
              labels |> List.map (fun { pld_name = { txt = n }; pld_type = typ } ->
                [%expr
                  Format.fprintf fmt "@[%s =@ " [%e str n];
                  [%e thrd3 @@ expr_of_typ quoter typ] [%e evar (argl n)];
                  Format.fprintf fmt "@]"
                ])
            in
            let printer =
              [%expr
                Format.fprintf fmt [%e str ("@[<2>" ^  constr_name ^ " {@,")];
                [%e args |> Ppx_deriving.(fold_exprs
                      (seq_reduce ~sep:[%expr Format.fprintf fmt ";@ "]))];
                Format.fprintf fmt "@]}"]
            in
            Exp.case (pconstrrec name' (pattl labels)) printer
          )
      in
      [%expr fun fmt -> [%e Exp.function_ cases]]
    | Ptype_variant _,_ -> assert false
    (* | Ptype_record labels, _ ->
      let fields =
        labels |> List.mapi (fun i { pld_name = { txt = name }; pld_type; pld_attributes } ->
          let field_name = if i = 0 then Ppx_deriving.expand_path ~path name else name in
          let pld_type = {pld_type with ptyp_attributes=pld_attributes@pld_type.ptyp_attributes} in
          [%expr
            Format.fprintf fmt "@[%s =@ " [%e str field_name];
            [%e expr_of_typ quoter pld_type] [%e Exp.field (evar "x") (mknoloc (Lident name))];
            Format.fprintf fmt "@]"
          ])
      in
      [%expr fun fmt x ->
        Format.fprintf fmt "@[<2>{ ";
        [%e fields |> Ppx_deriving.(fold_exprs
              (seq_reduce ~sep:[%expr Format.fprintf fmt ";@ "]))];
        Format.fprintf fmt "@ }@]"] *)
    | Ptype_record labels, _ -> assert false
    | Ptype_abstract, None ->
      raise_errorf ~loc "%s cannot be derived for fully abstract types" deriver
    | Ptype_open, _        ->
      raise_errorf ~loc "%s cannot be derived for open types" deriver
  in

  let pp_poly_apply =
    (* Ppx_deriving.poly_apply_of_type_decl type_decl (evar
      (Ppx_deriving.mangle_type_decl (`Prefix "pppt") type_decl)) *)

    List.fold_left (fun acc  (x,_) ->
      match x.ptyp_desc with
      | Ptyp_var s ->
        [%expr [%e acc] [%e Exp.ident @@ lid ("typ__"^s) ] [%e Exp.ident @@ lid ("poly_"^s) ] ]
      | _ -> assert false
    )
    (evar (Ppx_deriving.mangle_type_decl (`Prefix "pppt") type_decl))
    type_decl.ptype_params
  in

  let stringprinter = [%expr fun x -> Format.asprintf "%a" [%e pp_poly_apply] x] in
  (* let polymorphize  = Ppx_deriving.poly_fun_of_type_decl type_decl in *)
  let polymorphize =
    List.fold_right (fun (x,_) acc ->
        match x.ptyp_desc with
        | Ptyp_var s -> fun body -> [%expr fun [%p Pat.var (mknoloc @@ "typ__"^ s)]
                                               [%p Pat.var (mknoloc @@ "poly_"^ s)] -> [%e acc body]]
        | _ -> assert false
      )
      type_decl.ptype_params
      (fun x -> x)
  in
  let pp_type =
    Ppx_deriving.strong_type_of_type @@ pp_type_of_decl ~options ~path type_decl in
  let show_type =
    Ppx_deriving.strong_type_of_type @@
      show_type_of_decl ~options ~path type_decl in
  let pp_var =
    pvar (Ppx_deriving.mangle_type_decl (`Prefix "pppt") type_decl) in
  let show_var =
    pvar (Ppx_deriving.mangle_type_decl (`Prefix "show") type_decl) in
  [ Vb.mk pp_var
          (Ppx_deriving.sanitize ~quoter (polymorphize prettyprinter))
  (* ; Vb.mk (Pat.constraint_ pp_var pp_type)
          (Ppx_deriving.sanitize ~quoter (polymorphize prettyprinter)) *)
  (* ; Vb.mk (Pat.constraint_ show_var show_type) (polymorphize stringprinter) *)
  ; Vb.mk show_var (polymorphize stringprinter)
  ]

let () =
  Ppx_deriving.(register (create deriver
    (* ~core_type: (Ppx_deriving.with_quoter (fun quoter typ ->
      [%expr fun x -> Format.asprintf "%a" (fun fmt -> [%e expr_of_typ quoter typ]) x])) *)
    ~type_decl_str: (fun ~options ~path type_decls ->
      [Str.value Recursive (List.concat (List.map (str_of_type ~options ~path) type_decls))])
    (* ~type_decl_sig: (fun ~options ~path type_decls ->
      List.concat (List.map (sig_of_type ~options ~path) type_decls)) *)
    ()
  ))
