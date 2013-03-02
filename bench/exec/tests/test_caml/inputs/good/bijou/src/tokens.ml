type token = 
  | WHERE
  | UNLESS
  | TYPE
  | TRY
  | TRUE
  | THEN
  | TAG of (Identifier.t)
  | SUPPORT
  | SUBSET
  | SORT
  | SETUNION
  | SETMINUS
  | SETINTER
  | RPAR
  | RANGLE
  | RAISE
  | PATONE
  | PATAND
  | OUTER
  | OF
  | NOTHING
  | NOTEQ
  | LPAR
  | LET
  | LEMMA
  | LANGLE
  | INNER
  | IN
  | IFF
  | IF
  | ID of (Identifier.t)
  | FUN
  | FRESH
  | FORALL
  | FALSE
  | FAIL
  | EXCEPTION
  | EOF
  | END
  | EMPTYSET
  | ELSE
  | ELLIPSIS
  | DOT
  | DISJOINT
  | DEFEQ
  | COMMA
  | COLON
  | CMPEQ
  | CLOSED
  | CHECK
  | CASE
  | BOUND
  | BOR
  | BOOL
  | BNOT
  | BINDS
  | BAR
  | BAND
  | ATOMSET
  | ATOM
  | ASSERT
  | ARROW
  | ABSURD
