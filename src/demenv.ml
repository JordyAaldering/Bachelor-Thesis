open Printf

exception DemEnvFailure of string

type dem_env = (string, int array) Hashtbl.t

let mk_dem_env: unit -> dem_env = fun () ->
    Hashtbl.create 100

(* Helper function for debugging *)
let dem_env_find_and_raise st p expected msg =
    let exists = try Hashtbl.find st p; true with Not_found -> false in
    if expected <> exists then
        raise @@ DemEnvFailure msg

let dem_env_set: dem_env -> string -> int array -> unit = fun st x dem ->
    try
        let dem_old = Hashtbl.find st x in
        let dem_oplus = Array.map2 max dem dem_old in
        Hashtbl.replace st x dem_oplus
    with Not_found ->
        Hashtbl.add st x dem

let dem_env_combine: dem_env -> dem_env -> dem_env = fun xs ys ->
    let union = Hashtbl.copy xs in 
    Hashtbl.iter (fun y dem_y ->
        try
            let dem_x = Hashtbl.find union y in
            let dem_max = Array.map2 max dem_x dem_y in
            Hashtbl.replace union y dem_max;
        with Not_found ->
            Hashtbl.add union y dem_y;
    ) ys;
    union

let dem_env_remove: dem_env -> string -> unit = fun st p ->
    Hashtbl.remove st p

let dem_env_lookup: dem_env -> string -> int array = fun st p ->
    dem_env_find_and_raise st p true
        @@ sprintf "Attempt to lookup non-existing pointer `%s'" p;
    Hashtbl.find st p

let dem_env_to_str: dem_env -> string = fun st ->
    Hashtbl.fold (fun k v tail ->
        sprintf "%s -> %s\n%s" k (String.concat ", " (Array.to_list (Array.map string_of_int v))) tail
    ) st ""
