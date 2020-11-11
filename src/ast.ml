open Loc
open Printf

exception ParseFailure of string

type expr = {
    loc: loc;
    kind: expr_kind
}

and expr_kind =
    | EVar of string
    | EConst of float
    | EArray of expr list

    | EApply of expr * expr
    | ELetIn of string * expr * expr
    | EIfThen of expr * expr * expr

    | EBinary of binary_op * expr * expr
    | EUnary of unary_op * expr

    | ESel of expr * expr
    | EShape of expr
    | EDim of expr

and binary_op =
    | OpPlus
    | OpMinus
    | OpMult
    | OpDiv
    | OpMod
    | OpEq
    | OpNe
    | OpLt
    | OpLe
    | OpGt
    | OpGe

and unary_op =
    | OpNeg
    | OpNot


(** Constructors  **)

let mk_expr_var ?(loc=Internal) x =
    { loc=loc; kind=EVar x }

let mk_expr_const ?(loc=Internal) x =
    { loc=loc; kind=EConst x }

let mk_expr_array ?(loc=Internal) xs =
    { loc=loc; kind=EArray xs }

let mk_expr_apply lhs rhs =
    let { loc=l } = lhs in
    { loc=l; kind=EApply (lhs, rhs) }

let mk_expr_letin ?(loc=Internal) x e1 e2 =
    { loc=loc; kind=ELetIn (x, e1, e2) }

let mk_expr_ifthen ?(loc=Internal) p t f =
    { loc=loc; kind=EIfThen (p, t, f) }

let mk_expr_binary op lhs rhs =
    let { loc=l } = lhs in
    { loc=l; kind=EBinary (op, lhs, rhs) }

let mk_expr_unary ?(loc=Internal) op arg =
    { loc=loc; kind=EUnary (op, arg) }

let mk_expr_sel iv v =
    let { loc=l } = iv in
    { loc=l; kind=ESel (iv, v) }

let mk_expr_shape ?(loc=Internal) v =
    { loc=loc; kind=EShape v }

let mk_expr_dim ?(loc=Internal) v =
    { loc=loc; kind=EDim v }


(** Predicates **)

let expr_get_var_name e = match e with
    | { kind=EVar x } -> Some x
    | _ -> None

let rec cmp_ast_noloc e1 e2 = match e1, e2 with
    | { kind=EVar x }, { kind=EVar y } -> x = y
    | { kind=EConst x }, { kind=EConst y } -> x = y
    | { kind=EArray xs }, { kind=EArray ys } ->
        List.length xs = List.length ys
        && (List.fold_left2 (fun res x y -> res && cmp_ast_noloc x y) true xs ys)

    | { kind=EApply (x1, y1) }, { kind=EApply (x2, y2) } ->
        cmp_ast_noloc x1 x2
        && cmp_ast_noloc y1 y2
    | { kind=ELetIn (v1, x1, y1) }, { kind=ELetIn (v2, x2, y2) } ->
        v1 = v2
        && cmp_ast_noloc x1 x2
        && cmp_ast_noloc y1 y2
    | { kind=EIfThen (x1, y1, z1) }, { kind=EIfThen (x2, y2, z2) } ->
        cmp_ast_noloc x1 x2
        && cmp_ast_noloc y1 y2
        && cmp_ast_noloc z1 z2

    | { kind=EBinary (op1, x1, y1) }, { kind=EBinary (op2, x2, y2) } ->
        op1 = op2
        && cmp_ast_noloc x1 x1
        && cmp_ast_noloc y1 y2
    | { kind=EUnary (op1, x1) }, { kind=EUnary (op2, x2) } ->
        op1 = op2
        && cmp_ast_noloc x1 x2

    | { kind=ESel (x1, y1) }, { kind=ESel (x2, y2) } ->
        cmp_ast_noloc x1 x2
        && cmp_ast_noloc y1 y2
    | { kind=EShape x }, { kind=EShape y } ->
        cmp_ast_noloc x y
    | { kind=EDim x }, { kind=EDim y } ->
        cmp_ast_noloc x y
    
    | _ -> false


(** Printing **)

let rec expr_to_str e = match e with
    | { kind=EVar x } -> sprintf "%s" x
    | { kind=EConst x } -> string_of_float x
    | { kind=EArray xs } -> sprintf "[%s]"
        (String.concat ", " (List.map expr_to_str xs))

    | { kind=EApply (e1, e2) } ->
        sprintf "((%s) (%s))" (expr_to_str e1) (expr_to_str e2)
    | { kind=ELetIn (x, e1, e2) } ->
        sprintf "let %s = %s in %s" x (expr_to_str e1) (expr_to_str e2)
    | { kind=EIfThen (e1, e2, e3) } ->
        sprintf "if %s then %s else %s" (expr_to_str e1) (expr_to_str e2) (expr_to_str e3)

    | { kind=EBinary (bop, e1, e2) } ->
        sprintf "(%s) %s (%s)" (expr_to_str e1) (bop_to_str bop) (expr_to_str e2)
    | { kind=EUnary (uop, e1) } ->
        sprintf "%s(%s)" (uop_to_str uop) (expr_to_str e1)

    | { kind=ESel (e1, e2) } ->
        sprintf "sel (%s) (%s)" (expr_to_str e1) (expr_to_str e2)
    | { kind=EShape e1 } ->
        sprintf "shape (%s)" (expr_to_str e1)
    | { kind=EDim e1 } ->
        sprintf "dim (%s)" (expr_to_str e1)

and bop_to_str bop = match bop with
    | OpPlus -> "+"
    | OpMinus -> "-"
    | OpMult -> "*"
    | OpDiv -> "/"
    | OpMod -> "%"
    | OpEq -> "="
    | OpNe -> "!="
    | OpLt -> "<"
    | OpLe -> "<="
    | OpGt -> ">"
    | OpGe -> ">="

and uop_to_str uop = match uop with
    | OpNeg -> "-"
    | OpNot -> "!"