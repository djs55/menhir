open Sig
open Positions
open Misc

module Make 
  (Algebra: Algebra)
  (Rank: Rank) :
  MultiEquation with module Algebra = Algebra 
  =
struct
  module Algebra = Algebra
(*  module Ast = Ast*)
  open Algebra

  module Rank = Rank
  
  type variable =
      descriptor UnionFind.point

  (** A descriptor contains several pieces of information, the most
      important of which is the structure of the multi-equation, or,
      in other words, its unique non-variable member, if there is one.

      If the [structure] field is [None], then the multi-equation only
      has variable members. If it is [Some t], then the multi-equation
      contains a non-variable member, namely the term [t]. Note that
      [t] is a term whose head symbol belongs to the algebra and whose
      parameters are again variables. Thus, the unifier works with
      so-called ``small terms'' only.

      The [rank] field contains the rank currently attached to the
      multi-equation.

      The [mark] field is transient, and may be used by the unifier's
      client for any purpose. *) 
  and descriptor = {
      mutable structure: structure option;
      mutable rank: Rank.t;
      mutable mark: Mark.t;
      mutable kind: variable_kind;
      mutable name: string option;
      mutable pos: position option;
      mutable var: variable option;
      mutable variance: variance list option;
    } 

  and structure = variable Algebra.term

  (** A variable can be either flexible or rigid. In the second case, 
    a name has been given by the user. *)
  and variable_kind = Rigid | Flexible | Constant

  type name = string

  type crterm = variable Algebra.arterm

  type pool = {
      number: int; (** The present pool's rank. *)
      mutable inhabitants: variable list
    } 

  (** [new_pool pool] returns a new empty pool, whose number is the successor
      of [pool]'s. *)
  let new_pool pool = {
    number = pool.number + 1;
    inhabitants = []
  } 

  (** [init] produces a fresh initial state. It consists of an empty
      environment and a fresh, empty pool. *)
  let init () =
    {
      number = Rank.outermost;
      inhabitants = []
    }

  (** [register pool v] adds [v] to the pool [pool]. It is assumed that [v]'s
      rank is already set, so it is not modified. *)
  let register pool v =
    pool.inhabitants <- v :: pool.inhabitants

  (** [introduce pool v] adds [v] to the pool [pool]. [v]'s rank is set to the
      pool's number. It is assumed that it was previously uninitialized. *)
  let introduce pool v =
    let desc = UnionFind.find v in
      (*          if desc.kind = Constant then update v; *)
      desc.rank <- pool.number;
      register pool v 

    (* TEMPORARY time to perform the occur check on the variables which we
       just ranked [none]. On peut 'eventuellement integrer l'occur check
       a la derniere passe de realisation? *)

    (* Every variable that was initially a member of [young_pool] may now be
       viewed as the entry point of a type scheme. The body of the type scheme
       is the term obtained by traversing the structure below the entry
       point. The type scheme's universally quantified variables have rank
       [none], while its free variables have nonnegative ranks. 

       Note that, when considering several such variables, the type schemes
       that they represent may share some of their structure. No copying is
       involved. *)

       
   (*--------------------------------------------------------------*)    
 
   exception CyclicVariable of variable
   
   let non_cyclic_variable var_root = 

    let cyclic_mark = Mark.fresh() in
    
    let rec check_rec v =     
      let desc = UnionFind.find v in            
      if Mark.same desc.mark cyclic_mark 
        then raise (CyclicVariable v);            
      match desc.structure with
        | None -> ()  
        | Some structure ->   
            desc.mark <- cyclic_mark;
            iter check_rec structure;
            desc.mark <- Mark.none; 
      in
      
    check_rec var_root

     
  let rec non_cyclic_term = function
    | TVariable v  -> non_cyclic_variable v
    | TTerm t -> iter non_cyclic_term t
    | TGen (v, term) -> non_cyclic_term term

      
    (* use only be algo below *)
  let copy_gen_var position desc = 
    if (desc.rank <> Rank.none || desc.kind <> Rigid || desc.structure <> None)
      then failwith "Error in copy_gen_var: illegal rank, kind, or structure";
    let desc' = 
      {
        structure = None;  
        mark = Mark.none; 
        kind = Rigid;        
        rank = Rank.none; 
        name = None;
        pos = Some position; 
        var = None;
        variance = None;
      } 
      in
    UnionFind.fresh desc'
   
    
   let instance_crterm position term =  
     let mark_copied = Mark.fresh() in
     let rec copy_rec = function
      | TVariable v -> 
          TVariable (
            if Mark.same mark_copied (UnionFind.find v).mark  
              then unSome (UnionFind.find v).var
              else v
          )  
      | TTerm t -> TTerm (map copy_rec t)
      | TGen (v, subterm) ->     
          let desc = UnionFind.find v in   
          let v' = copy_gen_var position desc in
          desc.mark <- mark_copied;
          desc.var <- Some v';
          let sub' = copy_rec subterm in
          desc.var <- None;
          TGen (v', sub')
      in
      
    copy_rec term 
    
                 
  (* we only run on the part with rank young_number, *)
  let extract_generalizable_crterm young_number mark_gen var_root =

    let leaves = ref [] in
    
    let rec extract_rec v =
      
      let desc = UnionFind.find v in           
      if desc.rank < young_number then (
        (* case 1 : subtree contains nothing to generalize *)  
        TVariable v          
      ) else (
        match desc.structure with
        | None ->                
            (* case 2 : reaching a variable that will be generalize *)
            assert (desc.kind = Rigid);
            if not (Mark.same mark_gen desc.mark) 
              then (desc.mark <- mark_gen; leaves := v::(!leaves); );
            TVariable v   
         
        | Some structure ->      
            (* case 3 : node containing at least one variable to be generalized *)  
            TTerm (map extract_rec structure)      
      )    
      in
    let extracted = extract_rec var_root in
    !leaves, extracted 
    

       (*--------------------------------------------------------------*)    
     
       
  (* [instance] DEPRECATED : old invariant 
    val instance_deprecated : pool -> variable -> variable
  *)
  let instance_deprecated pool v =

    (* [get], [set], and [setp] implement a constant-time mapping from
       descriptors of rank [none] to variables. [mapped] allows determining
       whether a given descriptor belongs to the domain of the
       mapping. [associate] and [retrieve] respectively allow extending and
       looking up the mapping.

       In order to implement a constant-time mapping without wasting extra
       space, we re-use the descriptor's [rank] field, which is redundant at
       this point, since its value must be [none], and store a pointer in
       it. The field is to be viewed as containing a pointer if and only if
       the descriptor is marked with [m]. *)

    let m =
      Mark.fresh() in

    let setp desc =
      Mark.same desc.mark m

    and set desc v =
      desc.mark <- m;
      desc.var <- Some v

    and get desc =
      unSome desc.var
    in

    (* If [v] has rank [none], then [copy v] returns a copy of the variable
       [v], and copies its descendants recursively. The copy is registered in
       the current pool and given the current rank. If [v] has nonnegative
       rank, then [copy v] returns [v]. Only one copy per variable is created,
       even if a variable is found twice during the traversal. *)

    let rec copy v =

      let desc = UnionFind.find v in

      (* If a copy has been created already for this variable, return it. We
         must check this condition first, since we must not read [desc.rank]
         unless we know that the variable hasn't been copied yet. *)
        
      if setp desc then 
        get desc

      (* Otherwise, check the variable's rank. If it is other than [none],
         then the variable must not be copied. *)

      else if (desc.rank <> Rank.none || desc.kind = Constant)
      then 
        v

      (* Otherwise, the variable must be copied. We create a new variable,
         update the mapping, then update the new variable's descriptor. Note
         that the mapping must be updated before making a recursive call to
         [copy], so as to guarantee termination in the presence of cyclic
         terms. *)

      else 
        let desc' = 
            {
              structure = None;
              rank = pool.number;
              mark = Mark.none; 
              kind = Flexible;
              (* Prendre une instance d'une variable rigide, c'est parler
                 d'une variable differente. On ne propage donc pas le nom.
              *)
              name = (match desc.kind with Rigid -> None | _ -> desc.name);
              pos = None;
              var = None;
              variance = None;
            } 
        in
        let v' = UnionFind.fresh desc' in
          register pool v';
          set desc v';
          let v' = 
            match desc.structure with
              | None ->
                  v'
              | Some term ->
                  desc'.structure <- Some (map copy term);
                  v'
          in
            v'

    (* If [v] was effectively copied by [copy], then [restore v] returns
       [v] to its original state (that is, restores its rank to [none])
       and restores its descendants recursively. If [v] was not copied,
       [restore v] has no effect. *)

    and restore v =
      let desc = UnionFind.find v in
      if setp desc then begin
        desc.mark <- Mark.none;
        desc.rank <- Rank.none;
        match desc.structure with
          | None ->
              ()
          | Some term ->
              iter restore term
      end

    in

    (* We are now ready to take an instance of the type scheme whose
       entry point is [v]. It is simply a matter of copying [v] and
       its descendants, stopping at non-universally-quantified nodes.
       The copy process affects the type scheme, which must be restored
       afterwards. The whole process is linear in the size of the type
       scheme, that is, in the number of universally quantified nodes. *)
    let v' = copy v in
    restore v;
    v'

  (** [chop pool term] adds appropriate fresh variables and
      multi-equations to the environment and returns a variable
      which, according to these multi-equations, is equal to the term
      [term]. In other words, it turns a term of arbitrary depth into
      a variable, together with a number of multi-equations of depth
      at most one. *)
  let rec chop pool = function

    | TVariable v ->
        v

    | TTerm term ->
        let v =
          UnionFind.fresh 
            { (* TEMPORARY invoquer une fonction de c'reation dans Unifier? *)
              structure = Some (map (chop pool) term);
              rank = pool.number;
              mark = Mark.none;
              kind = Flexible;
              name = None;
              pos  = None;
              var = None;
              variance = None;
            } in
          register pool v;
          v

    | TGen _ -> failwith "multi-equation : chop should not receive any TGen"

  (** [variable()] creates a new variable, whose rank is [none]. *)
  let variable kind ?name ?structure ?pos () =
    UnionFind.fresh {
      structure = structure;
      rank = Rank.none;
      mark = Mark.none;
      kind = kind;
      name = name;
      pos = pos;
      var = None;
      variance = None;
    } 

  (** [variable_for_typecon variances] returns a new variable describing a type constructor. *)
  let variable_for_typecon ?name ?pos variance =
    UnionFind.fresh {
      structure = None;
      rank = Rank.none;
      mark = Mark.none;
      kind = Constant;
      name = name;
      pos = pos;
      var = None;
      variance = Some variance;
    } 
  
  let variance_of_constructor var_cons =
    match (UnionFind.find var_cons).variance with
      | Some v -> v
      | None -> failwith "variance_of_constructor: undefined" 
      
      
  let explode t = 
    let pool = 
      {
        number = Rank.outermost;
        inhabitants = []
      }
    in
    let v = chop pool t in
      match (UnionFind.find v).structure with
          None -> Var v
        | Some t -> t

  let variable_name v = (UnionFind.find v).name

  let variable_kind v = (UnionFind.find v).kind
 
  let variable_rank v = (UnionFind.find v).rank

  let set_rank r v = (UnionFind.find v).rank <- r

  let has_rank_none v = (variable_rank v = Rank.none)
  
  let set_rank_none v = set_rank Rank.none v
 
  let has_mark m v = Mark.same m (UnionFind.find v).mark

  let set_mark m v = (UnionFind.find v).mark <- m
 
  let is_rigid v = 
    let kind = variable_kind v in
      kind = Rigid || kind = Constant

  let set_flexible v =
    let desc = UnionFind.find v in
    desc.kind <- Flexible
  
  
  let is_structured v = (UnionFind.find v).structure <> None

  let variable_structure v = (UnionFind.find v).structure

  let type_variables t =
    List.filter (notf is_structured) (Algebra.type_variables t)

  let is_redundant = UnionFind.redundant

  let are_equivalent v1 v2 = UnionFind.equivalent v1 v2

  let inhabitants p = p.inhabitants

  let number p = p.number

  (** [variable()] returns a new variable. *)
  let variable kind ?name ?structure ?pos () = 
    let structure = 
      match structure with 
        | Some t -> 
            let pool = 
              {
                number = Rank.none;
                inhabitants = []
              }
            in
            
            let v = chop pool t in 
              Some (Var v)
        | None -> None
    in
      variable kind ?name:name ?structure:structure ?pos:pos ()

  (** [variable_list xs] allocates a fresh variable for every element in the 
    list [xs], and returns both a list of these variables and an association 
    list that maps elements to variables, viewed as types. *)
  let variable_list ?pos kind xs =
    List.fold_right (fun x (vs, xts) ->
                       let v = variable kind ?pos:pos () in
                         v :: vs, (x, v) :: xts
                    ) xs ([], [])
      
  (** [variable_list_from_strings f xs] allocates a fresh variable for every 
    string in the list [xs], and returns both a list of these variables 
    and an association list that maps elements to variables, viewed as types. *)
  let variable_list_from_strings ?pos kind xs =
    List.fold_right 
      (fun x (vs, xts) ->
         let k, n = kind x in
      let v = (* we do not want variables generated by elaboration to be named *)
        match n with 
          | Some n when String.length n >= 2 && n.[0] = '_' && n.[1] = '_' 
            -> variable k ?pos:pos ()
          | _ -> variable k ?name:n ?pos:pos ()
        in
      v :: vs, (x, v) :: xts
    ) xs ([], [])

  (** [variable_set xs] allocates a fresh variable for every element in the
      set [xs], and returns both a list of these variables and a map of
      elements to variables, viewed as types. *)
  let variable_set ?pos kind xs =
    StringSet.fold 
      (fun x (vs, xts) ->
         let k, n = kind x in
         let v = variable k ?name:n ?pos:pos () in
           v :: vs, StringMap.add x ((TVariable v), undefined_position) xts
      ) xs ([], StringMap.empty)

end