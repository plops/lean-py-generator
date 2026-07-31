import Lean

open Lean

namespace PyGenerator

/-- Abstract Syntax Tree representation for dynamic Common Lisp S-expression forms -/
inductive SExpr where
  | sym   (s : String)
  | str   (s : String)
  | int   (i : Int)
  | float (f : Float)
  | key   (k : String)
  | list  (items : List SExpr)
deriving BEq, Repr, Inhabited

namespace SExpr

def isSym : SExpr → Bool
  | sym _ => true
  | _     => false

def getSym? : SExpr → Option String
  | sym s => some s
  | _     => none

def isStr : SExpr → Bool
  | str _ => true
  | _     => false

def getStr? : SExpr → Option String
  | str s => some s
  | _     => none

def isList : SExpr → Bool
  | list _ => true
  | _      => false

def getList? : SExpr → Option (List SExpr)
  | list items => some items
  | _          => none

end SExpr

/-- Group flat list of S-expressions into pairs of (key, value) -/
def groupPairs : List SExpr → List (SExpr × SExpr)
  | a :: b :: rest => (a, b) :: groupPairs rest
  | _ => []

/-- Length upper-bound theorem for groupPairs -/
theorem groupPairs_length_le (l : List SExpr) : (groupPairs l).length * 2 <= l.length := by
  match l with
  | [] => simp [groupPairs]
  | [_] => simp [groupPairs]
  | a :: b :: rest =>
    have ih := groupPairs_length_le rest
    simp [groupPairs]
    omega
termination_by l.length

/-- Split parameter list into positional arguments and keyword arguments -/
def splitArgs (args : List SExpr) : List SExpr × List (String × SExpr) :=
  let rec loop (rest : List SExpr) (pos : List SExpr) (kw : List (String × SExpr)) :=
    match rest with
    | [] => (pos.reverse, kw.reverse)
    | SExpr.key k :: v :: xs => loop xs pos ((k, v) :: kw)
    | x :: xs => loop xs (x :: pos) kw
  loop args [] []

end PyGenerator
