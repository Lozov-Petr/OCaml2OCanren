type 'a expression = I
                   | O
                   | Var of 'a
                   | Not of 'a expression
                   | Conj of 'a expression * 'a expression
                   | Disj  of 'a expression * 'a expression

type 'a maybe = Just of 'a | Nothing

type ('a, 'b) binding = Pair of 'a * 'b

let (>>=) e f =
  match e with
  | Nothing -> Nothing
  | Just x  -> f x


let rec lookup s n =
  match s with
  | []    -> Nothing
  | x::xs ->
    match x with
    | Pair (m, e) -> if n = m then Just e else lookup xs n


let rec eval subst expr =
  match expr with
  | I           -> Just true
  | O           -> Just false
  | Var x       -> lookup subst x
  | Not e       -> eval subst e >>= fun b -> Just (not b)
  | Conj (l, r) -> eval subst l >>= fun a -> eval subst r >>= fun b -> Just (a && b)
  | Disj (l, r) -> eval subst l >>= fun a -> eval subst r >>= fun b -> Just (a || b)


(************************************************************************)

let conj_true a b =
  match a with
  | true -> b


let rec append a b =
  match a with
  | []    -> b
  | x::xs -> x :: append xs b

let rec remove v l =
  match l with
  | []    -> []
  | x::xs -> let nl = remove v xs in if v = x then nl else x :: nl

let rec remove_repeats l =
  match l with
  | []    -> []
  | x::xs -> x :: remove_repeats (remove x xs)

let rec all_vars e =
  match e with
  | I           -> []
  | O           -> []
  | Var x       -> [x]
  | Not e       -> all_vars e
  | Conj (l, r) -> append (all_vars l) @@ all_vars r
  | Disj (l, r) -> append (all_vars l) @@ all_vars r

let check_subst subst expr =
  let rec check subst vars =
    match vars with
    | []    -> subst = []
    | x::xs ->
      match subst with
      | y::ys ->
        match y with
        | Pair (a, b) -> conj_true (x = a) (check ys xs) in
   check subst (all_vars expr)

let check_and_eval subst expr =
  Just (check_subst subst expr) >>= fun x -> eval subst expr >>= fun y -> Just (x && y)

(************************************************************************)

let expr1 = O
let expr2 = Disj (Var "ok", I)
let expr3 = Conj (Var "ok", I)

let expr4 =
  Disj (Conj (Var "X", Var "Y"), Conj (Var "Z", Not (Var "Last")))

let a = false
