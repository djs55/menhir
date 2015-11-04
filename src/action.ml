open Keyword

type t = {

  (* The code for this semantic action. *)
  expr: IL.expr;

  (* The files where this semantic action originates. Via inlining,
     several semantic actions can be combined into one, so there can
     be several files. *)
  filenames: string list;

  (* A list of keywords that appear in this semantic action, with their
     positions. This list is maintained only up to the well-formedness check in
     [PartialGrammar.check_keywords]. Thereafter, it is no longer used. So, the
     keyword-renaming functions do not bother to update it. *)
  pkeywords : keyword Positions.located list;

  (* The set of keywords that appear in this semantic action. They can be thought
     of as free variables that refer to positions. They must be renamed during
     inlining. *)
  keywords  : KeywordSet.t;

}

(* Creation. *)

let pkeywords_to_keywords pkeywords =
  KeywordSet.of_list (List.map Positions.value pkeywords)

let from_stretch s = 
  let pkeywords = s.Stretch.stretch_keywords in
  { 
    expr      = IL.ETextual s;
    filenames = [ s.Stretch.stretch_filename ];
    pkeywords = pkeywords;
    keywords  = pkeywords_to_keywords pkeywords;
  }

(* Composition, used during inlining. *)

let compose x a1 a2 = 
  (* 2015/07/20: there used to be a call to [parenthesize_stretch] here,
     which would insert parentheses around every stretch in [a1]. This is
     not necessary, as far as I can see, since every stretch that represents
     a semantic action is already parenthesized by the lexer. *)
  {
    expr      = IL.ELet ([ IL.PVar x, a1.expr ], a2.expr);
    keywords  = KeywordSet.union a1.keywords a2.keywords;
    filenames = a1.filenames @ a2.filenames;
    pkeywords = [] (* don't bother; already checked *)
  }

(* Renaming of keywords, used during inlining. *)

type sw =
  Keyword.subject * Keyword.where

type keyword_renaming =
  string * sw * sw

let rename_inlined_psym ((psym, first_prod, last_prod) : keyword_renaming) phi keywords =
  let phi = ref phi in
  let keywords =
    KeywordSet.map (fun keyword ->
       match keyword with
	 | Position (subject, where, flavor) ->
	     let (subject', where') = 
	       match subject, where with
		 | RightNamed s, w  -> 
		     (* In the host rule, $startpos(x) is changed 
			to $startpos(first_prod) (same thing for $endpos). *)
		     if s = psym then
		       match w with
			 | WhereStart -> first_prod
			 | WhereEnd   -> last_prod
		     else 
		       (* Otherwise, we just take the renaming into account. *)
		       let s' = try 
			 List.assoc s !phi
		       with Not_found -> s 
		       in
			 (RightNamed s', w)
		 | Left, _ -> (subject, where)
	     in
	     let from_pos = Keyword.posvar subject where flavor
	     and to_pos = Keyword.posvar subject' where' flavor in
	     if from_pos <> to_pos && not (List.mem_assoc from_pos !phi) then
		   phi := (from_pos, to_pos) :: !phi;
	     Position (subject', where', flavor)

	 | SyntaxError -> SyntaxError
    )
  keywords
  in
  keywords, !phi

(* Rename the keywords related to position to handle the composition
   of semantic actions during non terminal inlining. 

   The first argument describes the context: 
   - [first_prod] is the first producer that starts the action's rule.
   - [last_prod] is the last one.
   For instance, if %inline rule r is A -> B C and rule r' is D -> E A F,
   then [first_prod] is B and [last_prod] is C. 
   If r is A -> and r' is unchanged. [first_prod] is E and [last_prod] is F.
   - [psym] is the producer that is being inlined.
   
*)
let rename_pkeywords (psym, first_prod, last_prod) phi keywords = 
  let phi = ref phi in
  let keywords =
    KeywordSet.map (fun keyword ->
      match keyword with
      | Position (subject, where, flavor) ->
		let (subject', where') = 
		  match subject, where with
		      (* $startpos is changed to $startpos(first_prod) in the 
			 inlined rule. *)
		    | Left, WhereStart -> first_prod
		      (* Similarly for $endpos. *)
		    | Left, WhereEnd   -> last_prod
		    | RightNamed s, w  -> 
			(* In the host rule, $startpos(x) is changed to 
			   to $startpos(first_prod) (same thing for $endpos). *)
			if s = psym then
			  match w with
			    | WhereStart -> first_prod;
			    | WhereEnd -> last_prod
			else 
			  (* Otherwise, we just take the renaming into account. *)
			  let s' = try List.assoc s !phi with Not_found -> s in
			    (RightNamed s', w)
		in
		let from_pos = Keyword.posvar subject where flavor
		and to_pos = Keyword.posvar subject' where' flavor in
	        if from_pos <> to_pos && not (List.mem_assoc from_pos !phi) then
		  phi := (from_pos, to_pos) :: !phi;
	        Position (subject', where', flavor)

	 | SyntaxError -> SyntaxError
    )
  keywords
  in
  keywords, !phi
		
let rename renaming_fun keyword_renaming phi a = 
  let keywords, phi = renaming_fun keyword_renaming phi a.keywords in
  { a with 
      (* We use the let construct to rename without modification of the semantic
	 action code. *)
      expr = 
      IL.ELet (List.map (fun (x, x') -> (IL.PVar x, IL.EVar x')) phi, 
	       a.expr);

      (* Keywords related to positions are updated too. *)
      pkeywords = []; (* don't bother *)
      keywords  = keywords;
  }

let rename_inlined_psym =
  rename rename_inlined_psym

let rename =
  rename rename_pkeywords

let to_il_expr action = 
  action.expr

let filenames action = 
  action.filenames

let keywords action = 
  action.keywords

let pkeywords action = 
  action.pkeywords

let print f action = 
  let module P = Printer.Make (struct let f = f 
				      let locate_stretches = None 
			       end) 
  in
    P.expr action.expr

let has_syntaxerror action =
  KeywordSet.mem SyntaxError (keywords action)

let has_leftstart action =
  KeywordSet.exists (function
    | Position (Left, WhereStart, _) ->
	true
    | _ ->
	false
  ) (keywords action)

let has_leftend action =
  KeywordSet.exists (function
    | Position (Left, WhereEnd, _) ->
	true
    | _ ->
	false
  ) (keywords action)

