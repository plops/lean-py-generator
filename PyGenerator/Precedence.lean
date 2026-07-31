import Lean

open Lean

namespace PyGenerator

inductive Assoc | left | right
deriving BEq, Repr, Inhabited

structure OpSpec where
  ops : List String
  assoc : Assoc
deriving Repr, Inhabited

def precedenceTable : List OpSpec := [
  { ops := ["paren", "paren*", "dict", "list", "tuple", "curly", "aref", "dot"], assoc := .left },
  { ops := ["**"], assoc := .right },
  { ops := ["unary-", "unary+", "~"], assoc := .right },
  { ops := ["*", "@", "/", "//", "%"], assoc := .left },
  { ops := ["+", "-"], assoc := .left },
  { ops := ["<<", ">>"], assoc := .left },
  { ops := ["&", "logand"], assoc := .left },
  { ops := ["^", "logxor"], assoc := .left },
  { ops := ["|", "logior"], assoc := .left },
  { ops := ["<", "<=", ">", ">=", "!=", "==", "in", "not-in", "is", "is-not"], assoc := .left },
  { ops := ["not"], assoc := .right },
  { ops := ["and"], assoc := .left },
  { ops := ["or"], assoc := .left },
  { ops := ["?", "ternary"], assoc := .right },
  { ops := ["=", "setf"], assoc := .right }
]

def lookupPrecedence (op : String) : Option Nat :=
  precedenceTable.findIdx? (fun spec => spec.ops.contains op)

def lookupAssociativity (op : String) : Assoc :=
  match precedenceTable.find? (fun spec => spec.ops.contains op) with
  | some spec => spec.assoc
  | none => .left

def allOperators : List String :=
  precedenceTable.bind (·.ops)

/-- Theorem: Unrecognized operators default deterministically to left associativity -/
theorem lookupAssociativity_default (op : String) (h : precedenceTable.find? (fun spec => spec.ops.contains op) = none) :
    lookupAssociativity op = Assoc.left := by
  unfold lookupAssociativity
  rw [h]
  rfl

end PyGenerator
