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

Import-Module (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\AstFunctions.ps1') -Force

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
        # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
        $automaticVariableNames = (
            '$$', '$?', '$^', '$_', '$args', '$ConsoleFileName', '$EnabledExperimentalFeatures', '$Error', '$Event',
            '$EventArgs', '$EventSubscriber', '$ExecutionContext', '$false', '$foreach', '$HOME', '$Host', '$input',
            '$IsCoreCLR', '$IsLinux', '$IsMacOS', '$IsWindows', '$LASTEXITCODE', '$Matches', '$MyInvocation',
            '$NestedPromptLevel', '$null', '$PID', '$PROFILE', '$PSBoundParameters', '$PSCmdlet', '$PSCommandPath',
            '$PSCulture', '$PSDebugContext', '$PSEdition', '$PSHOME', '$PSItem', '$PSScriptRoot', '$PSSenderInfo',
            '$PSUICulture', '$PSVersionTable', '$PWD', '$Sender', '$ShellId', '$StackTrace', '$switch', '$this', '$true')

        $analyzerViolations = New-Object System.Collections.Generic.List[Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]

        try
        {
            $rootIndex = '$'
            $functionParameters = @{}
            $functionParameters[$rootIndex] = @()

            Find-AstParameters -AstObject $Ast | ForEach-Object { $functionParameters[$rootIndex] += $PSItem.Name.Extent.Text }

            $functions = $ast.FindAll(
                {
                    param([Ast] $AstObject)
                    return ($AstObject -is [FunctionDefinitionAst])
                },
                $true
            )

            $functions | ForEach-Object {
                $functionName = $PSItem.Name
                Find-AstParameters -AstObject $PSItem | ForEach-Object { $functionParameters[$functionName] += $PSItem.Name.Extent.Text }
            }

            $functionParametersWithParents = @{}
            $functionParametersWithParents[$rootIndex] = $functionParameters[$rootIndex]
            $functions | ForEach-Object {
                $functionName = $PSItem.Name

                $parents = Find-AstParents -AstObject $PSItem -ParentType ([FunctionDefinitionAst])

                $functionParametersWithParents[$functionName] += $functionParameters[$rootIndex]
                $functionParametersWithParents[$functionName] += $functionParameters[$functionName]
                $parents | Select-Object -ExpandProperty Name | ForEach-Object {
                    $functionParametersWithParents[$functionName] += $functionParameters[$PSItem]
                }
            }

            $Ast.FindAll(
                {
                    param([Ast] $AstObject)
                    return ($AstObject -is [VariableExpressionAst])
                },
                $true
            ) | ForEach-Object {
                $variableName = $PSItem.Extent.Text

                $automaticVariable = $automaticVariableNames | Where-Object {
                    $PSItem -eq $variableName } | Select-Object -First 1

                # The '-ceq' operator should work here, but it doesn't.
                if ($null -ne $automaticVariable -and -not $automaticVariable.Equals($variableName, 'InvariantCulture'))
                {
                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $PSItem.Extent
                        'Message' = @(
                            "Automatic variables should be used with the correct casing: '$automaticVariable'"
                            "instead of '$variableName'."
                        ) -join ' '
                        'RuleName' = 'PSUseCorrectAutomaticVariableNameCasing'
                        'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNameCasing'
                        'Severity' = 'Warning'
                    }
                }

                $nearestParentFunction = (Find-AstNearestParent -AstObject $PSItem -ParentType ([FunctionDefinitionAst]))

                if ([string]::IsNullOrEmpty($nearestParentFunction))
                {
                    $nearestParentFunctionName = $rootIndex
                }
                else
                {
                    $nearestParentFunctionName = $nearestParentFunction.Name
                }

                if ($variableName -NotMatch '(?-i)^\$[a-z].*' -and $functionParametersWithParents[$nearestParentFunctionName] -notcontains $variableName)
                {
                    Write-Warning "$($variableName) line $($PSItem.Extent.StartLineNumber) column $($PSItem.Extent.StartColumnNumber)"
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
