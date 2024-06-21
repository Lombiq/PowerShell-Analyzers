<#
.SYNOPSIS
    Detects inconsistencies in the casing of parameter names and variable names (including automatic variables).
.DESCRIPTION
    Raises the following warnings regarding the casing of parameter names and variable names (including automatic
    variables):
    - PSUseCorrectParameterNameCasing: Parameter names should contain only alphanumeric characters and start with an
      uppercase letter.
    - PSUseCorrectAutomaticVariableNameCasing: Automatic variables should be used with the casing according to the
      documentation:
      https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
    - PSUseParameterNameDeclaredCasing: Parameters should be used with the declared casing.
    - PSUseCorrectVariableNameCasing: Variable names should contain only alphanumeric characters and start with a
      lowercase letter.
.EXAMPLE
    Measure-VariableNameCasing -Ast $Ast
.INPUTS
    [System.Management.Automation.Language.ScriptBlockAst]
.OUTPUTS
    [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>

using namespace System.Management.Automation.Language

Import-Module (Join-Path (Split-Path -Path $MyInvocation.MyCommand.Path) '..\AstFunctions.ps1') -Force

function Measure-VariableNameCasing
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $Ast
    )

    Process
    {
        $analyzerViolations = New-Object System.Collections.Generic.List[Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]

        # This analyzer can and should analyze the whole file only, especially if it has embedded functions, because it
        # needs to keep track of parameters declared in the root and the parent functions of a given function.
        if ($Ast.Extent.StartLineNumber -ne 1 -or $Ast.Extent.StartColumnNumber -ne 1)
        {
            return $analyzerViolations
        }

        # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
        $automaticVariableNames = (
            '$$', '$?', '$^', '$_', '$args', '$ConsoleFileName', '$EnabledExperimentalFeatures', '$Error', '$Event',
            '$EventArgs', '$EventSubscriber', '$ExecutionContext', '$false', '$foreach', '$HOME', '$Host', '$input',
            '$IsCoreCLR', '$IsLinux', '$IsMacOS', '$IsWindows', '$LASTEXITCODE', '$Matches', '$MyInvocation',
            '$NestedPromptLevel', '$null', '$PID', '$PROFILE', '$PSBoundParameters', '$PSCmdlet', '$PSCommandPath',
            '$PSCulture', '$PSDebugContext', '$PSEdition', '$PSHOME', '$PSItem', '$PSScriptRoot', '$PSSenderInfo',
            '$PSUICulture', '$PSVersionTable', '$PWD', '$Sender', '$ShellId', '$StackTrace', '$switch', '$this', '$true')

        try
        {
            # The whole script block being analyzed is the root, which we call '€$', since it doesn't have a name.
            $rootIndex = '€$'
            $functionParameters = @{}
            $functionParameters[$rootIndex] = @()

            # Extract parameters from the root.
            Find-AstParameters -AstObject $Ast | ForEach-Object { $functionParameters[$rootIndex] += $PSItem.Name.Extent.Text }

            # Extract all the functions.
            $functions = $ast.FindAll(
                {
                    param([Ast] $AstObject)
                    return ($AstObject -is [FunctionDefinitionAst])
                },
                $true
            )

            # Extract the parameters from the functions.
            foreach ($function in $functions)
            {
                $functionParameters[$function.Name] = @()

                foreach ($parameter in Find-AstParameters -AstObject $function)
                {
                    $parameterName = $parameter.Name.Extent.Text

                    $functionParameters[$function.Name] += $parameterName

                    # Check if the parameter name starts with an uppercase letter.
                    if ($parameterName -NotMatch '(?-i)^\$[A-Z].*')
                    {
                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $parameter.Extent
                            'Message' = "Parameter names should start with an uppercase letter: '$parameterName'."
                            'RuleName' = 'PSUseCorrectParameterNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectParameterNameCasing'
                            'Severity' = 'Warning'
                        }
                    }
                }
            }

            # Set up a new dictionary that contains the parameters of the functions and their parents (root included).
            $functionParametersWithParents = @{}
            $functionParametersWithParents[$rootIndex] = $functionParameters[$rootIndex]
            foreach ($function in $functions)
            {
                $parentFunctions = Find-AstParents -AstObject $function -ParentType ([FunctionDefinitionAst])

                # Add the parameters of the function itself.
                $functionParametersWithParents[$function.Name] += $functionParameters[$function.Name]
                # Add the parameters of the parent functions.
                foreach ($parentFunction in $parentFunctions)
                {
                    $functionParametersWithParents[$function.Name] += $functionParameters[$parentFunction.Name]
                }
                # Add the parameters of the root.
                $functionParametersWithParents[$function.Name] += $functionParameters[$rootIndex]
            }

            # Iterate through each variable expression in the whole AST.
            $variables = $Ast.FindAll(
                {
                    param([Ast] $AstObject)
                    return ($AstObject -is [VariableExpressionAst])
                },
                $true
            )

            foreach ($variable in $variables)
            {
                $variableName = $variable.Extent.Text

                # Check if the variable is an automatic variable.
                $automaticVariable = $automaticVariableNames | Where-Object {
                    $PSItem -eq $variableName } | Select-Object -First 1

                # If an automatic variable is found, check if it's used with the correct casing. The '-ceq' operator
                # should work here, but it doesn't.
                if ($null -ne $automaticVariable)
                {
                    if (-not $automaticVariable.Equals($variableName, 'InvariantCulture'))
                    {
                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = @(
                                "Automatic variables should be used with the correct casing: '$automaticVariable'"
                                "instead of '$variableName'."
                            ) -join ' '
                            'RuleName' = 'PSUseCorrectAutomaticVariableNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNameCasing'
                            'Severity' = 'Warning'
                        }
                    }

                    continue
                }

                # Find the nearest parent function of the variable.
                $nearestParentFunction = (Find-AstNearestParent -AstObject $variable -ParentType ([FunctionDefinitionAst]))

                # If there is no explicit parent function found, then the variable is in the root.
                if ([string]::IsNullOrEmpty($nearestParentFunction))
                {
                    $nearestParentFunctionName = $rootIndex
                }
                else
                {
                    $nearestParentFunctionName = $nearestParentFunction.Name
                }

                # Check if the variable is a parameter.
                $matchingParameter = $functionParametersWithParents[$nearestParentFunctionName] | Where-Object {
                    $PSItem -eq $variableName } | Select-Object -First 1

                # If the variable is not a parameter, check if it starts with a lowercase letter.
                if ($null -eq $matchingParameter)
                {
                    if ($variableName -NotMatch '(?-i)^\$[a-z].*')
                    {
                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = "Variable names should start with a lowercase letter: '$variableName'."
                            'RuleName' = 'PSUseCorrectVariableNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectVariableNameCasing'
                            'Severity' = 'Warning'
                        }
                    }

                    continue
                }
                # If a parameter is found, check if it's used with the declared casing. The '-ceq' operator should work
                # here, but it doesn't.
                elseif (-not $matchingParameter.Equals($variableName, 'InvariantCulture'))
                {
                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $variable.Extent
                        'Message' = @(
                            "Parameters should be used with the declared casing: '`$matchingParameter' instead of"
                            "'$variableName'."
                        ) -join ' '
                        'RuleName' = 'PSUseParameterNameDeclaredCasing'
                        'RuleSuppressionID' = 'PSUseParameterNameDeclaredCasing'
                        'Severity' = 'Warning'
                    }

                    continue
                }
            }

            return $analyzerViolations
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}
