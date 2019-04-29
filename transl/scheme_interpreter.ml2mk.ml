type variable = First | Next of variable

type identifier = Lambda | Quote | List | Var of variable

type term = Ident of identifier | Seq of term list

type result = Val of term | Closure of identifier * term * (identifier * result) list

let rec map f l =
  match l with
  | x :: xs -> f x :: map f xs
  | []      -> []

let rec lookup x env =
  match env with
  | (y, res) :: env' ->
    if x = y then res else lookup x env'

let rec not_in_env x env =
  match env with
  | [] -> true
  | (y, res) :: env' ->
     if x = y then false else not_in_env x env'

let rec eval term env =

  let lambda_handler ts env =
    match not_in_env Lambda env with
    | true ->
      match ts with
      | [Seq [Ident i]; body] ->
        Closure (i, body, env) in

  let quote_handler ts env =
    match not_in_env Quote env with
    | true ->
      match ts with
      | [t] -> Val t in

  let list_handler ts env =
    match not_in_env List env with
    | true ->
      let eval_val t = match eval t env with Val v -> v in
      Val (Seq (map eval_val ts)) in

  match term with
  | Ident x -> lookup x env
  | Seq (t :: ts) ->
    match t with
    | Ident id ->
      begin match id with
      | Lambda -> lambda_handler ts env
      | Quote  -> quote_handler  ts env
      | List   -> list_handler   ts env
      end
    | Seq s ->
      match ts with
      | [arg] ->
        match eval t env with
        | Closure (x, body, env') ->
          eval body ((x, eval arg env) :: env')



(* let x      = Ident (Var First)
let quotE  = Ident Quote
let lambdA = Ident Lambda
let lisT   = Ident List
let s x    = Seq x

let quine_func = s [lambdA; s [x]; s [lisT; x; s [lisT; s [quotE; quotE]; x]]]
let quine_arg  = s [quotE; quine_func]

let quine =      s [quine_func; quine_arg] *)
