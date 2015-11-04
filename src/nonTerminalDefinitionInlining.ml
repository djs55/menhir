open UnparameterizedSyntax
open ListMonad

(* This exception will be raised when a branch does not need inlining. *)
exception NoInlining

(* Color are used to detect cycles. *)
type 'a color = 
  | BeingExpanded
  | Expanded of 'a

(* Inline a grammar. The resulting grammar does not contain any definitions
   that can be inlined. *)
let inline grammar = 

  let names producers = 
    List.fold_left (fun s (_, x) -> StringSet.add x s) 
      StringSet.empty producers 
  in

  (* This function returns a fresh name beginning with [prefix] and 
     that is not in the set of names [names]. *)
  let rec fresh ?(c=0) names prefix =
    let name = prefix^string_of_int c in
      if StringSet.mem name names then
	fresh ~c:(c+1) names prefix
      else 
	name
  in

  let use_inline = ref false in

  (* This table associates a color to each non terminal that can be expanded. *)
  let expanded_non_terminals = 
    Hashtbl.create 13 
  in

  let expanded_state k = 
    Hashtbl.find expanded_non_terminals k 
  in
      
  let mark_as_being_expanded k = 
    Hashtbl.add expanded_non_terminals k BeingExpanded
  in

  let mark_as_expanded k r =
    Hashtbl.replace expanded_non_terminals  k (Expanded r);
    r
  in

  (* This function traverses the producers of the branch [b] and find
     the first non terminal that can be inlined. If it finds one, it
     inlines its branches into [b], that's why this function can return
     several branches. If it does not find one non terminal to be 
     inlined, it raises [NoInlining]. *)
  let rec find_inline_producer b = 
    let prefix, nt, p, psym, suffix = 
      let rec chop_inline i (prefix, suffix) =
	match suffix with
	  | [] -> 
	      raise NoInlining

	  | ((nt, id) as x) :: xs ->
	      try
		let r = StringMap.find nt grammar.rules in
		if r.inline_flag then 
		    (* We have to inline the rule [r] into [b] between
		       [prefix] and [xs]. *)
		  List.rev prefix, nt, r, id, xs
		else 
		  chop_inline (i + 1) (x :: prefix, xs) 
	      with Not_found -> 
		chop_inline (i + 1) (x :: prefix, xs) 
      in
	chop_inline 1 ([], b.producers)
    in
      prefix, expand_rule nt p, nt, psym, suffix

  (* We have to rename producers' names of the inlined production 
     if they clashes with the producers' names of the branch into 
     which we do the inlining. *)
  and rename_if_necessary b producers =

    (* First we compute the set of names already in use. *)
    let producers_names = names (b.producers @ producers) in

    (* Compute a renaming and the new inlined producers' names. *)
    let phi, producers' =
      List.fold_left (fun (phi, producers) (p, x) -> 
	if StringSet.mem x producers_names then
	  let x' = fresh producers_names x in
	  ((x, x') :: phi, (p, x') :: producers)
	else 
	  (phi, (p, x) :: producers)
      ) ([], []) producers
    in
      phi, List.rev producers'
	
  (* Inline the non terminals that can be inlined in [b]. We use the 
     ListMonad to combine the results. *)
  and expand_branch (b : branch) : branch ListMonad.m =
    try
      let prefix, p, _nt, psym, suffix = find_inline_producer b in
      use_inline := true;
      (* Inline a branch of [nt] at position [prefix] ... [suffix] in
	 the branch [b]. *)
      let inline_branch pb =
	(* Rename the producers of this branch is they conflict with
	   the name of the host's producers. *)
	let phi, inlined_producers = rename_if_necessary b pb.producers in

	(* Define the renaming environment given the shape of the branch. *)
	  let start_position =
	    match List.rev prefix with

	      (* If the prefix is empty, the start position is the rule
		 start position. *)
	      | [] -> (Keyword.Left, Keyword.WhereStart)

	      (* The last producer of prefix is named [x],
		 $startpos in the inlined rule will be changed to $endpos(x). *)
	      | (_, x) :: _ -> (Keyword.RightNamed x, Keyword.WhereEnd)

	  in
	  (* Same thing for the suffix. *)
	  let end_position =
	    match suffix with
	      | [] -> (Keyword.Left, Keyword.WhereEnd)
	      | (_, x) :: _ -> (Keyword.RightNamed x, Keyword.WhereStart)
	  in

	let renaming_env =
	  (psym, start_position, end_position)
	in
	(* Rename the host semantic action.
	   Each reference of the inlined non terminal [psym] must be taken into
	   account. $startpos(psym) is changed to $startpos(x) where [x] is
	   the first producer of the inlined branch if it is not empty or
	   the preceding producer found in the prefix. *)
	let outer_action =
	  Action.rename_inlined_psym renaming_env [] b.action
	in
	let action' =
	  Action.rename renaming_env phi pb.action
	in

	{ b with
	  producers = prefix @ inlined_producers @ suffix;
	  action = Action.compose psym action' outer_action
	}
      in
      List.map inline_branch p.branches >>= expand_branch

    with NoInlining ->
      return b

  (* Expand a rule if necessary. *)
  and expand_rule k r = 
    try 
      (match expanded_state k with
	 | BeingExpanded ->
    	     Error.error
	       r.positions
	       "there is a cycle in the definition of %s." k
	 | Expanded r ->
	     r)
    with Not_found ->
      mark_as_being_expanded k;
      mark_as_expanded k { r with branches = r.branches >>= expand_branch }
  in

  (* If we are in Coq mode, %inline is forbidden. *)
  let _ =
    if Settings.coq then
      StringMap.iter 
        (fun _ r -> 
	   if r.inline_flag then
             Error.error r.positions
               "%%inline is not supported by the Coq back-end.")
        grammar.rules
  in

    (* To expand a grammar, we expand all its rules and remove 
       the %inline rules. *)
  let expanded_rules = 
    StringMap.mapi expand_rule grammar.rules
  and useful_types = 
      StringMap.filter 
	(fun k _ -> try not (StringMap.find k grammar.rules).inline_flag
	 with Not_found -> true)
	grammar.types
  in

    { grammar with 
	rules = StringMap.filter (fun _ r -> not r.inline_flag) expanded_rules;
	types = useful_types
    }, !use_inline
      
