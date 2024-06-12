<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
    Measure-VariableNameCasing -Token $Token
.INPUTS
    [System.Management.Automation.Language.Token[]]
.OUTPUTS
    [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>

function Measure-VariableNameCasing
{
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.Token[]]
        $Token
    )

    Process
    {
        $results = @()
        $parameterNames = @()
        $paramTokenFound = $false
        $parenthesisDepth = 0
        $scriptBlockFound = $false
        $scriptBlockDepth = 0
        # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
        $automaticVariableNames = (
            'args', 'ConsoleFileName', 'EnabledExperimentalFeatures', 'Error', 'Event', 'EventArgs', 'EventSubscriber',
            'ExecutionContext', 'false', 'foreach', 'HOME', 'Host', 'input', 'IsCoreCLR', 'IsLinux', 'IsMacOS',
            'IsWindows', 'LASTEXITCODE', 'Matches', 'MyInvocation', 'NestedPromptLevel', 'null', 'PID', 'PROFILE',
            'PSBoundParameters', 'PSCmdlet', 'PSCommandPath', 'PSCulture', 'PSDebugContext', 'PSEdition', 'PSHOME',
            'PSItem', 'PSScriptRoot', 'PSSenderInfo', 'PSUICulture', 'PSVersionTable', 'PWD', 'Sender', 'ShellId',
            'StackTrace', 'switch', 'this', 'true')

        try
        {
            foreach ($token in $Token)
            {
                # *******
                # STEP 1: Find the Param block and check the parameter names.
                # *******

                # Find the Param token to start looking for parameter names.
                if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Param)
                {
                    $paramTokenFound = $true

                    continue
                }

                if ($paramTokenFound)
                {
                    # Find '(' tokens to increase the parenthesis depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LParen)
                    {
                        $parenthesisDepth++

                        continue
                    }

                    # Find ')' tokens to decrease the parenthesis depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::RParen)
                    {
                        $parenthesisDepth--

                        # If the parenthesis depth reaches 0, we have reached the end of the Param block.
                        if ($parenthesisDepth -eq 0)
                        {
                            $paramTokenFound = $false
                        }

                        continue
                    }

                    # If we are inside the parameter list and the parenthesis depth is 1, we are looking at parameter
                    # names.
                    if ($parenthesisDepth -eq 1 -and $token.Kind -eq [System.Management.Automation.Language.TokenKind]::Variable)
                    {
                        $parameterNames += $token.Name

                        # If the parameter name is not in the correct format, add a diagnostic record.
                        if ($token.Name -NotMatch '(?-i)^[A-Z][a-zA-Z0-9]*')
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $token.Extent
                                'Message' = @(
                                    'Parameter names should contain only alphanumeric characters and start with an'
                                    "uppercase letter: '$($token.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectParameterNameStyling'
                                'RuleSuppressionID' = 'PSUseCorrectParameterNameStyling'
                                'Severity' = 'Warning'
                            }
                        }
                    }
                }

                # *******
                # STEP 2: Find script blocks and check the variable names against the automatic variables, the known
                # parameters and the correct format.
                # *******

                # Find a token corresponding to a script block to start looking for variable names.
                if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Begin -or
                    $token.Kind -eq [System.Management.Automation.Language.TokenKind]::Process -or
                    $token.Kind -eq [System.Management.Automation.Language.TokenKind]::End)
                {
                    $scriptBlockFound = $true

                    continue
                }

                if ($scriptBlockFound)
                {
                    # Find '{' tokens to increase the script block depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly)
                    {
                        $scriptBlockDepth++

                        continue
                    }

                    # Find '}' tokens to decrease the script block depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::RCurly)
                    {
                        $scriptBlockDepth--

                        # If the parenthesis depth reaches 0, we have reached the end of the script block.
                        if ($scriptBlockDepth -eq 0)
                        {
                            $scriptBlockFound = $false
                        }

                        continue
                    }

                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Variable)
                    {
                        # *******
                        # STEP 2.1: Find automatic variables that are used with the wrong casing.
                        # *******

                        $automaticVariable = $automaticVariableNames | Where-Object {
                            $PSItem.ToLowerInvariant() -eq $token.Name.ToLowerInvariant() } | Select-Object -First 1

                        if ($null -ne $automaticVariable -and -not $automaticVariable.Equals($token.Name, 'InvariantCulture'))
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $token.Extent
                                'Message' = @(
                                    "Automatic variables should be used with the correct casing: '$automaticVariable'"
                                    "instead of '$($token.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectAutomaticVariableNameStyling'
                                'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNameStyling'
                                'Severity' = 'Warning'
                            }

                            continue
                        }

                        # *******
                        # STEP 2.2: Find parameters that are used with the wrong casing.
                        # *******

                        if ($parameterNames.Length -gt 0)
                        {
                            $parameter = $parameterNames | Where-Object {
                                $PSItem.ToLowerInvariant() -eq $token.Name.ToLowerInvariant() } | Select-Object -First 1

                            if ($null -ne $parameter -and -not $parameter.Equals($token.Name, 'InvariantCulture'))
                            {
                                $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                    'Extent' = $token.Extent
                                    'Message' = @(
                                        "Parameters should be used with the declared casing: '$parameter' instead of"
                                        "'$($token.Name)'."
                                    ) -join ' '
                                    'RuleName' = 'PSUseCorrectParameterNameStyling'
                                    'RuleSuppressionID' = 'PSUseCorrectParameterNameStyling'
                                    'Severity' = 'Warning'
                                }

                                continue
                            }
                        }

                        # *******
                        # STEP 2.3: Find variables that are used with the wrong casing.
                        # *******

                        if ($false -and $token.Name -NotMatch '(?-i)^[a-z][a-zA-Z0-9]*')
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $token.Extent
                                'Message' = @(
                                    'Variable names should contain only alphanumeric characters and start with a'
                                    "lowercase letter: '$($token.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectVariableNameStyling'
                                'RuleSuppressionID' = 'PSUseCorrectVariableNameStyling'
                                'Severity' = 'Warning'
                            }
                        }
                    }
                }
            }

            return $results
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}
