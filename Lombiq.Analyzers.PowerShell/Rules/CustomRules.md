# Custom analyzer rules

Our custom analyzer rules are automatically included when using `Invoke-Analyzer.ps1` or GitHub Actions.

- `Measure-AutomaticVariableAlias`: Detects the usages of the alias `$_` of the automatic variable `$PSItem` and suggests to correct them.
- `Measure-LineContinuation`: Detects the usages of the backtick (line continuation) character.
- `Measure-VariableNameCasing`: Detects inconsistencies in the casing of parameter names and variable names (including automatic variables).
