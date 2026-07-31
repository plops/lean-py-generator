import Lake
open Lake DSL

package «lean-py-generator» where
  -- add package configuration options here

lean_lib «PyGenerator» where
  -- add library configuration options here

@[default_target]
lean_exe «lean-py-generator» where
  root := `Main
