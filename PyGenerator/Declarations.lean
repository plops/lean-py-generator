import PyGenerator.AST

open Lean

namespace PyGenerator

structure Env where
  typeTable    : List (String × SExpr) := []
  captures     : List String := []
  returnValues : List SExpr := []
deriving Inhabited

def Env.lookupType (env : Env) (varName : String) : Option SExpr :=
  match env.typeTable.find? (fun (k, _) => k == varName) with
  | some (_, t) => some t
  | none        => none

def Env.insertType (env : Env) (varName : String) (typeExpr : SExpr) : Env :=
  { env with typeTable := (varName, typeExpr) :: env.typeTable }

/-- Parse type/capture/values declarations from function body forms -/
def consumeDeclare (body : List SExpr) : List SExpr × Env :=
  let rec loop (rest : List SExpr) (accBody : List SExpr) (env : Env) : List SExpr × Env :=
    match rest with
    | [] => (accBody.reverse, env)
    | e :: es =>
      match e with
      | SExpr.list (SExpr.sym "declare" :: decls) =>
        let newEnv := decls.foldl (fun env decl =>
          match decl with
          | SExpr.list (SExpr.sym "type" :: typeExpr :: vars) =>
            vars.foldl (fun env' v =>
              match v.getSym? with
              | some varName => env'.insertType varName typeExpr
              | none => env'
            ) env
          | SExpr.list (SExpr.sym "capture" :: vars) =>
            let capVars := vars.filterMap SExpr.getSym?
            { env with captures := env.captures ++ capVars }
          | SExpr.list (SExpr.sym "values" :: typesOpt) =>
            let filtered := typesOpt.filter (fun t =>
              match t with
              | SExpr.sym s => !s.startsWith "&"
              | _ => true
            )
            { env with returnValues := filtered }
          | _ => env
        ) env
        loop es accBody newEnv
      | _ => (accBody.reverse ++ rest, env)
  loop body [] {}

structure ParsedLambda where
  reqParam  : List String := []
  optParam  : List (String × Option SExpr) := []
  resParam  : Option String := none
  keyParam  : List (String × SExpr) := []
  auxParam  : List (String × Option SExpr) := []
deriving Inhabited

/-- Parse Common Lisp ordinary lambda list -/
def parseOrdinaryLambdaList (lambdaList : List SExpr) : ParsedLambda :=
  let rec parseReq (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym "&optional" :: rest => parseOpt rest acc
    | SExpr.sym "&rest" :: SExpr.sym r :: rest => parseRest rest { acc with resParam := some r }
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | SExpr.sym name :: rest => parseReq rest { acc with reqParam := acc.reqParam ++ [name] }
    | _ :: rest => parseReq rest acc

  and parseOpt (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym "&rest" :: SExpr.sym r :: rest => parseRest rest { acc with resParam := some r }
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | SExpr.sym name :: rest => parseOpt rest { acc with optParam := acc.optParam ++ [(name, none)] }
    | SExpr.list [SExpr.sym name, init] :: rest => parseOpt rest { acc with optParam := acc.optParam ++ [(name, some init)] }
    | _ :: rest => parseOpt rest acc

  and parseRest (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | SExpr.sym "&key" :: rest => parseKey rest acc
    | _ :: rest => parseRest rest acc
    | [] => acc

  and parseKey (args : List SExpr) (acc : ParsedLambda) : ParsedLambda :=
    match args with
    | [] => acc
    | SExpr.sym name :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, SExpr.sym "None")] }
    | SExpr.list [SExpr.sym name, init] :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, init)] }
    | SExpr.list [SExpr.list [SExpr.sym _, SExpr.sym name], init] :: rest => parseKey rest { acc with keyParam := acc.keyParam ++ [(name, init)] }
    | _ :: rest => parseKey rest acc

  parseReq lambdaList {}

end PyGenerator
