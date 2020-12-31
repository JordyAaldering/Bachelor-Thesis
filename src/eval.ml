open Ast
open Env
open Value
open Printf

exception EvalError of string

let eval_err msg =
    raise @@ EvalError msg

let ptr_count = ref 0

let create_fresh_ptr () =
    ptr_count := !ptr_count + 1;
    sprintf "p%d" !ptr_count

let add_fresh_value st v =
    let p = create_fresh_ptr () in
    let st = Env.add p v st in
    (st, p)

let update_let_ptr st p_old p_new =
    let value_updater v =
        match v with
            | VClosure (s, e, env) ->
                let env' = Env.map (fun p ->
                    if p = p_old then p_new else p
                ) env in
                VClosure (s, e, env')
            | _ -> v
    in Env.map value_updater st

let ptr_binary st op p1 p2 =
    let v1 = Env.find p1 st in
    let v2 = Env.find p2 st in
    match op with
        | OpAppend -> value_append v1 v2
        | OpAdd -> value_add v1 v2
        | OpMin -> value_add v1 (value_neg v2)
        | OpMul -> value_mul v1 v2
        | OpDiv -> value_div v1 v2
        | OpEq -> value_eq v1 v2
        | OpNe -> value_not @@ value_eq v1 v2
        | OpLt -> value_lt v1 v2
        | OpLe -> value_not @@ value_gt v1 v2
        | OpGt -> value_gt v1 v2
        | OpGe -> value_not @@ value_lt v1 v2

let ptr_unary st op p =
    let v = Env.find p st in
    match op with
        | OpNeg -> value_neg v
        | OpNot -> value_not v

let rec eval_expr e st env = match e with
    (* variables *)
    | EVar x -> (st, Env.find x env)
    | EFloat x -> add_fresh_value st (VArray ([], [x]))
    | EArray es ->
        let st, ptr_lst = eval_expr_lst es st env in
        let shp = [List.length ptr_lst] in
        let data = List.fold_right (fun ptr val_lst ->
                let ptr_val = Env.find ptr st in
                let float = (match ptr_val with
                    | VArray ([], [x]) -> x
                    | _ -> eval_err @@ sprintf "invalid value in list `%s'"
                            (value_to_str ptr_val)
                ) in
                float :: val_lst
            ) ptr_lst []
        in
        add_fresh_value st (VArray (shp, data))
    (* expressions *)
    | EApply (e1, e2) ->
        let st, p1 = eval_expr e1 st env in
        let st, p2 = eval_expr e2 st env in
        let x, body, env' = extract_closure (Env.find p1 st) in
        eval_expr body st (Env.add x p2 env')
    | ELambda (s, e1) ->
        add_fresh_value st (VClosure (s, e1, env))
    | ELet (x, e1, e2) ->
        let pname = create_fresh_ptr () in
        let st, p1 = eval_expr e1 st (Env.add x pname env) in
        let st = update_let_ptr st pname p1 in
        eval_expr e2 st (Env.add x p1 env)
    | ECond (e1, e2, e3) ->
        let st, p1 = eval_expr e1 st env in
        let v = Env.find p1 st in
        eval_expr (if value_is_truthy v then e2 else e3) st env
    (* operands *)
    | EBinary (op, e1, e2) ->
        let st, p1 = eval_expr e1 st env in
        let st, p2 = eval_expr e2 st env in
        let v = ptr_binary st op p1 p2 in
        add_fresh_value st v
    | EUnary (op, e1) ->
        let st, p = eval_expr e1 st env in
        let v = ptr_unary st op p in
        add_fresh_value st v
    (* primitive functions *)
    | ESel (e1, e2) ->
        let st, v1 = eval_expr e1 st env in
        let st, iv = eval_expr e2 st env in
        let v2 = sel (Env.find v1 st) (Env.find iv st) in
        add_fresh_value st v2
    | EShape e1 ->
        let st, p = eval_expr e1 st env in
        let v = shape (Env.find p st) in
        add_fresh_value st v
    | EDim e1 ->
        let st, p = eval_expr e1 st env in
        let v = dim (Env.find p st) in
        add_fresh_value st v
    | ERead ->
        printf "> ";
        let x = float_of_string @@ read_line () in
        add_fresh_value st (VArray ([], [x]))

and eval_expr_lst es st env = match es with
    | [] -> (st, [])
    | x :: xs ->
        let st, y = eval_expr x st env in
        let st, ys = eval_expr_lst xs st env in
        (st, y :: ys)

let eval e =
    ptr_count := 0;
    let st, p = eval_expr e Env.empty Env.empty in
    printf "%s\n" (value_to_str (Env.find p st))
