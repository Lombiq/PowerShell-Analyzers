<#
.SYNOPSIS
    Detects inconsistencies in the casing of parameter names and variable names (including automatic variables).
.DESCRIPTION
    Raises the following warnings regarding the casing of parameter names and variable names (including automatic
    variables):
    - PSAvoidUsingUnnecessaryBracesInVariableNames: Variable names should not use unnecessary braces.
    - PSUseCorrectAutomaticVariableNames: Automatic variables should be used exactly as they are documented:
      https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
    - PSUseCorrectParameterNameCasing: Parameter names should start with an uppercase letter.
    - PSUseCorrectVariableNameCasing: Variable names should start with a lowercase letter.
    - PSUseParametersAsDeclared: Parameters should be used with exactly as they were declared.

    When fixing warnings, work through the rules in the order they are listed above, because violating
    PSAvoidUsingUnnecessaryBracesInVariableNames and/or PSUseCorrectParameterNameCasing, while referencing that
    parameter with the correct casing or format, will also raise a PSUseParametersAsDeclared warning. The false
    positives for later rules should disappear once you fix the warnings raised by earlier rules.
.EXAMPLE
    Measure-VariableNameFormat -Ast $Ast
.INPUTS
    [System.Management.Automation.Language.ScriptBlockAst]
.OUTPUTS
    [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>

using namespace System.Management.Automation.Language

Import-Module (Join-Path (Split-Path -Path $MyInvocation.MyCommand.Path) '..\AstFunctions.ps1') -Force

function Measure-VariableNameFormat
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
            $rootParameters = Find-AstParameter -AstObject $Ast
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

            # Extract the parameters from the functions and put them into a dictionary with the function names as keys.
            foreach ($function in $functions)
            {
                $functionParameterNames[$function.Name] = @()

                $functionParameters = Find-AstParameter -AstObject $function
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
                if ($parameterName -Match '(?-i)^\$\{?[a-z].*')
                {
                    $correctedParameterName = ($parameterName.Substring(0, $firstLetterIndex) +
                        $parameterName.Substring($firstLetterIndex, 1).ToUpper() +
                        $parameterName.Substring($firstLetterIndex + 1))

                    $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                        $parameter.Name.Extent
                        $correctedParameterName
                        @(
                            "Corrected the casing of the parameter name from '$parameterName' to"
                            "'$correctedParameterName' to start with an uppercase letter."
                        ) -join ' '
                    )

                    $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                    $suggestedCorrections.add($correctionExtent) | Out-Null

                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $parameter.Name.Extent
                        'Message' = @(
                            "Parameter names should start with an uppercase letter: '$parameterName' should be"
                            "'$correctedParameterName'."
                        ) -join ' '
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
                $parentFunctions = Find-AstParent -AstObject $function -ParentType ([FunctionDefinitionAst])

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

                # Due to the added complexity vs. their usage frequency, skip scoped variables and path-like
                # expressions. Also skipping environment variables, where the casing doesn't matter.
                if ($variableName.Contains(':'))
                {
                    continue
                }

                # Check if the variable name contains braces unnecessarily, i.e., there are no special characters in it.
                if ($variableName -Match '(?-i)^\$\{[a-zA-Z\d]+\}')
                {
                    $bracelessVariableName = '$' + $variableName.Substring(2, $variableName.Length - 3)
                    $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                        $variable.Extent
                        $bracelessVariableName
                        @(
                            "Corrected the variable name '$variableName' to '$bracelessVariableName' not to use"
                            'unnecessary braces.'
                        ) -join ' '
                    )

                    $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                    $suggestedCorrections.add($correctionExtent) | Out-Null

                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $variable.Extent
                        'Message' = @(
                            "Variable names should not use unnecessary braces: '$variableName' should be"
                            "'$bracelessVariableName'."
                        ) -join ' '
                        'RuleName' = 'PSAvoidUsingUnnecessaryBracesInVariableNames'
                        'RuleSuppressionID' = 'PSAvoidUsingUnnecessaryBracesInVariableNames'
                        'Severity' = 'Warning'
                        'SuggestedCorrections' = $suggestedCorrections
                    }

                    continue
                }

                # Produce a variable name that is the opposite of '$variableName' in terms of having braces or not.
                $inverseBracedVariableName = $null
                if ($variableName.StartsWith('${'))
                {
                    $inverseBracedVariableName = '$' + $variableName.Substring(2, $variableName.Length - 3)
                }
                else
                {
                    $inverseBracedVariableName = '${' + $variableName.Substring(1) + '}'
                }

                # Check if the variable is an automatic variable.
                $automaticVariable = $automaticVariableNames |
                    Where-Object { $PSItem -eq $variableName -or $PSItem -eq $inverseBracedVariableName } |
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
                            "Corrected the usage of the '$variableName' automatic variable to '$automaticVariable'."
                        )

                        $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                        $suggestedCorrections.add($correctionExtent) | Out-Null

                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = @(
                                "Automatic variables should be used exactly as they are documented: '$variableName'"
                                "should be '$automaticVariable'."
                            ) -join ' '
                            'RuleName' = 'PSUseCorrectAutomaticVariableNames'
                            'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNames'
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

                # Check if the variable is a parameter, used with or without braces.
                $matchingParameter = $functionParameterNamesWithParents[$nearestParentFunctionName] | Where-Object {
                    $PSItem -eq $variableName -or $PSItem -eq $inverseBracedVariableName } | Select-Object -First 1

                # If the variable is not a parameter, check if it starts with a lowercase letter.
                if ($null -eq $matchingParameter)
                {
                    if ($variableName -Match '(?-i)^\$\{?[A-Z].*')
                    {
                        $firstLetterIndex = [Math]::Max($variableName.IndexOf('$'), $variableName.IndexOf('{')) + 1
                        $correctedVariableName = ($variableName.Substring(0, $firstLetterIndex) +
                            $variableName.Substring($firstLetterIndex, 1).ToLower() +
                            $variableName.Substring($firstLetterIndex + 1))

                        $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                            $variable.Extent
                            $correctedVariableName
                            "Corrected the casing of the variable name from '$variableName' to '$correctedVariableName'."
                        )

                        $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                        $suggestedCorrections.add($correctionExtent) | Out-Null

                        $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                            'Extent' = $variable.Extent
                            'Message' = @(
                                "Variable names should start with a lowercase letter: '$variableName' should be"
                                "'$correctedVariableName'."
                            ) -join ' '
                            'RuleName' = 'PSUseCorrectVariableNameCasing'
                            'RuleSuppressionID' = 'PSUseCorrectVariableNameCasing'
                            'Severity' = 'Warning'
                            'SuggestedCorrections' = $suggestedCorrections
                        }
                    }

                    continue
                }
                # If a parameter is found, check if it's used exactly as it was declared. The '-ceq' operator should
                # work here, but it doesn't.
                elseif (-not $matchingParameter.Equals($variableName, 'InvariantCulture'))
                {
                    $correctionExtent = New-Object -TypeName $correctionTypeName -ArgumentList @(
                        $variable.Extent
                        $matchingParameter
                        @(
                            "Corrected the usage of the parameter '$variableName' to '$matchingParameter' to match its"
                            'declaration.'
                        ) -join ' '
                    )

                    $suggestedCorrections = New-Object System.Collections.ObjectModel.Collection[$correctionTypeName]
                    $suggestedCorrections.add($correctionExtent) | Out-Null

                    $analyzerViolations += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        'Extent' = $variable.Extent
                        'Message' = @(
                            "Parameters should be used exactly as they were declared: '$variableName' should be"
                            "'$matchingParameter'."
                        ) -join ' '
                        'RuleName' = 'PSUseParametersAsDeclared'
                        'RuleSuppressionID' = 'PSUseParametersAsDeclared'
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
