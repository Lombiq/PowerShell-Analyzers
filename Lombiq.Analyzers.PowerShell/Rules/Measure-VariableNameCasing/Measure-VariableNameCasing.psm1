<#
.SYNOPSIS
    Detects inconsistencies in the casing of parameter names and variable names (including automatic variables).
.DESCRIPTION
    Raises the following warnings regarding the casing of parameter names and variable names (including automatic
    variables):
    - PSUseCorrectAutomaticVariableNameCasing: Automatic variables should be used with the casing according to the
      documentation:
      https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
    - PSUseCorrectParameterNameCasing: Parameter names should start with an uppercase letter.
    - PSUseParameterNameDeclaredCasing: Parameters should be used with the declared casing.
    - PSUseCorrectVariableNameCasing: Variable names should start with a lowercase letter.

    When fixing warnings, work through the rules in the order they are listed above, because violating
    PSUseCorrectParameterNameCasing, while referencing that parameter with the correct casing, will also raise a
    PSUseParameterNameDeclaredCasing warning. The latter will disappear after fixing the former.
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

        $correctionTypeName = 'Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.CorrectionExtent'
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
            $allParameters = @()
            $functionParameterNames = @{}
            $functionParameterNames[$rootIndex] = @()

            # Extract parameters from the root.
            $rootParameters = Find-AstParameters -AstObject $Ast
            $allParameters += $rootParameters
            $rootParameters | ForEach-Object { $functionParameterNames[$rootIndex] += $PSItem.Name.Extent.Text }

            # Extract all the functions.
            $functions = $Ast.FindAll(
                {
                    param([Ast] $astObject)
                    return ($astObject -is [FunctionDefinitionAst])
                },
                $true
            )

            # Extract the parameters from the functions.
            foreach ($function in $functions)
            {
                $functionParameterNames[$function.Name] = @()

                $functionParameters = Find-AstParameters -AstObject $function
                $allParameters += $functionParameters
                foreach ($parameter in $functionParameters)
                {
                    $functionParameterNames[$function.Name] += $parameter.Name.Extent.Text
                }
            }

            # Check all the parameters' names.
            foreach ($parameter in $allParameters)
            {
                $parameterName = $parameter.Name.Extent.Text
                $firstLetterIndex = [Math]::Max($parameterName.IndexOf('$'), $parameterName.IndexOf('{')) + 1

                # Check if the parameter name starts with an uppercase letter.
                if ($parameterName -NotMatch '(?-i)^\$\{?[A-Z].*')
                {
                    $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                        $parameter.Name.Extent
                        ($parameterName.Substring(0, $firstLetterIndex) + $parameterName.Substring($firstLetterIndex, 1).ToUpper() + $parameterName.Substring($firstLetterIndex + 1))
                        "Fixed the casing of the parameter name '$parameterName' to start with an uppercase letter."
                    )

                    $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                    $suggestedCorrections.add($correctionExtent) | Out-Null

                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $parameter.Name.Extent
                        'Message' = "Parameter names should start with an uppercase letter: '$parameterName'."
                        'RuleName' = 'PSUseCorrectParameterNameCasing'
                        'RuleSuppressionID' = 'PSUseCorrectParameterNameCasing'
                        'Severity' = 'Warning'
                        'SuggestedCorrections' = $suggestedCorrections
                    }
                }
            }

            # Set up a new dictionary that contains the parameters of the functions with their parents (and root)
            # included.
            $functionParameterNamesWithParents = @{}
            $functionParameterNamesWithParents[$rootIndex] = $functionParameterNames[$rootIndex]
            foreach ($function in $functions)
            {
                $parentFunctions = Find-AstParents -AstObject $function -ParentType ([FunctionDefinitionAst])

                # Add the parameters of the function itself.
                $functionParameterNamesWithParents[$function.Name] += $functionParameterNames[$function.Name]
                # Add the parameters of the parent functions.
                foreach ($parentFunction in $parentFunctions)
                {
                    $functionParameterNamesWithParents[$function.Name] += $functionParameterNames[$parentFunction.Name]
                }
                # Add the parameters of the root.
                $functionParameterNamesWithParents[$function.Name] += $functionParameterNames[$rootIndex]
            }

            # Extract each variable expression from the whole AST.
            $variables = $Ast.FindAll(
                {
                    param([Ast] $astObject)
                    return ($astObject -is [VariableExpressionAst])
                },
                $true
            )

            foreach ($variable in $variables)
            {
                $variableName = $variable.Extent.Text

                # Skip path-like expressions, including environment variables.
                if (-not $variableName.StartsWith('${') -and $variableName.Contains(':'))
                {
                    continue
                }

                # Skip variable expressions enclosed in braces.
                if ($variableName.Contains('{'))
                {
                    continue
                }

                # Check if the variable is an automatic variable.
                $automaticVariable = $automaticVariableNames | Where-Object { $PSItem -eq $variableName } |
                    Select-Object -First 1

                # If an automatic variable is found, check if it's used with the correct casing. The '-ceq' operator
                # should work here, but it doesn't.
                if ($null -ne $automaticVariable)
                {
                    if (-not $automaticVariable.Equals($variableName, 'InvariantCulture'))
                    {
                        $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                            $variable.Extent
                            $automaticVariable
                            "Updated the casing of the automatic variable from '$variableName' to '$automaticVariable'."
                        )

                        $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                        $suggestedCorrections.add($correctionExtent) | Out-Null

                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = @(
                                'Automatic variables should be used with the casing according to the documentation:'
                                "'$automaticVariable' instead of '$variableName'."
                            ) -join ' '
                            'RuleName' = 'PSUseCorrectAutomaticVariableNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNameCasing'
                            'Severity' = 'Warning'
                            'SuggestedCorrections' = $suggestedCorrections
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
                $matchingParameter = $functionParameterNamesWithParents[$nearestParentFunctionName] | Where-Object {
                    $PSItem -eq $variableName } | Select-Object -First 1

                # If the variable is not a parameter, check if it starts with a lowercase letter.
                if ($null -eq $matchingParameter)
                {
                    if ($variableName -NotMatch '(?-i)^[\$@]{?[a-z].*')
                    {
                        $correctedVariableName = ($variableName.Substring(0, $firstLetterIndex) + $variableName.Substring($firstLetterIndex, 1).ToLower() + $variableName.Substring($firstLetterIndex + 1))
                        $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                            $variable.Extent
                            $correctedVariableName
                            "Updated the casing of the variable from '$variableName' to '$correctedVariableName'."
                        )

                        $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                        $suggestedCorrections.add($correctionExtent) | Out-Null

                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = "Variable names should start with a lowercase letter: '$variableName'."
                            'RuleName' = 'PSUseCorrectVariableNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectVariableNameCasing'
                            'Severity' = 'Warning'
                            'SuggestedCorrections' = $suggestedCorrections
                        }
                    }

                    continue
                }
                # If a parameter is found, check if it's used with the declared casing. The '-ceq' operator should work
                # here, but it doesn't.
                elseif (-not $matchingParameter.Equals($variableName, 'InvariantCulture'))
                {
                    $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                        $variable.Extent
                        $matchingParameter
                        "Fixed the casing of the variable '$variableName' to match the parameter '$matchingParameter'."
                    )

                    $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                    $suggestedCorrections.add($correctionExtent) | Out-Null

                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $variable.Extent
                        'Message' = @(
                            "Parameters should be used with the declared casing: '$matchingParameter' instead of"
                            "'$variableName'."
                        ) -join ' '
                        'RuleName' = 'PSUseParameterNameDeclaredCasing'
                        'RuleSuppressionID' = 'PSUseParameterNameDeclaredCasing'
                        'Severity' = 'Warning'
                        'SuggestedCorrections' = $suggestedCorrections
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
