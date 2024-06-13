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
        # See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables.
        $automaticVariableNames = (
            'args', 'ConsoleFileName', 'EnabledExperimentalFeatures', 'Error', 'Event', 'EventArgs', 'EventSubscriber',
            'ExecutionContext', 'false', 'foreach', 'HOME', 'Host', 'input', 'IsCoreCLR', 'IsLinux', 'IsMacOS',
            'IsWindows', 'LASTEXITCODE', 'Matches', 'MyInvocation', 'NestedPromptLevel', 'null', 'PID', 'PROFILE',
            'PSBoundParameters', 'PSCmdlet', 'PSCommandPath', 'PSCulture', 'PSDebugContext', 'PSEdition', 'PSHOME',
            'PSItem', 'PSScriptRoot', 'PSSenderInfo', 'PSUICulture', 'PSVersionTable', 'PWD', 'Sender', 'ShellId',
            'StackTrace', 'switch', 'this', 'true')

        $results = @()

        $parameterNames = @()
        $parameterBlockFound = $false
        $parameterBlockParenthesisDepth = 0
        $parameterBlockProcessed = $false

        $scriptBlockFound = $false
        $scriptBlockDepth = 0

        try
        {
            for ($i = 0; $i -lt $Token.Count; $i++)
            {
                $currentToken = $Token[$i]

                # *******
                # STEP 0: Find the function token and reset the state.
                # *******
                if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Function)
                {
                    $parameterNames = @()
                    $parameterBlockFound = $false
                    $parameterBlockProcessed = $false

                    # *******
                    # STEP 1: Detect the inline parameter block.
                    # *******

                    # The token immediately following the function token is the function name. If the one following that
                    # is LParen, then the parameter block is inline.
                    if ($Token[$i + 2].Kind -eq [System.Management.Automation.Language.TokenKind]::LParen)
                    {
                        $parameterBlockFound = $true
                        $i++ # Skip the function name token.
                    }

                    continue
                }

                # *******
                # STEP 2: Detect the normal parameter block that starts with the Param token.
                # *******

                # If we haven't a found parameter block yet (inline or not), then look for the Param token.
                if (-not $parameterBlockFound -and -not $parameterBlockProcessed -and
                    $currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Param)
                {
                    $parameterBlockFound = $true

                    continue
                }

                # *******
                # STEP 3: Process the parameter block.
                # *******

                if ($parameterBlockFound -and -not $parameterBlockProcessed)
                {
                    # Find '(' tokens to increase the parenthesis depth.
                    if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::LParen)
                    {
                        $parameterBlockParenthesisDepth++

                        continue
                    }

                    # Find ')' tokens to decrease the parenthesis depth.
                    if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::RParen)
                    {
                        $parameterBlockParenthesisDepth--

                        # If the parenthesis depth reaches 0, we have reached the end of the Param block.
                        if ($parameterBlockParenthesisDepth -eq 0)
                        {
                            $parameterBlockProcessed = $true
                        }

                        continue
                    }

                    # If we are inside the parameter list and the parenthesis depth is 1, we are looking at parameter
                    # names.
                    if ($parameterBlockParenthesisDepth -eq 1 -and
                        $currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Variable -and
                        $automaticVariableNames -notcontains $currentToken.Name)
                    {
                        $parameterNames += $currentToken.Name

                        # If the parameter name is not in the correct format, add a diagnostic record.
                        if ($currentToken.Name -NotMatch '(?-i)^[A-Z][a-zA-Z0-9]*')
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $currentToken.Extent
                                'Message' = @(
                                    'Parameter names should contain only alphanumeric characters and start with an'
                                    "uppercase letter: '$($currentToken.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectParameterNameCasing'
                                'RuleSuppressionID' = 'PSUseCorrectParameterNameCasing'
                                'Severity' = 'Warning'
                            }
                        }
                    }
                }

                # *******
                # STEP 4: Find script blocks and check the variable names against the automatic variables, the known
                # parameters and the correct format.
                # *******

                # Find a token corresponding to a script block to start looking for variable names.
                if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Begin -or
                    $currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Process -or
                    $currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::End)
                {
                    $scriptBlockFound = $true

                    continue
                }

                if ($scriptBlockFound)
                {
                    # Find '{' tokens to increase the script block depth.
                    if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::LCurly)
                    {
                        $scriptBlockDepth++

                        continue
                    }

                    # Find '}' tokens to decrease the script block depth.
                    if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::RCurly)
                    {
                        $scriptBlockDepth--

                        # If the parenthesis depth reaches 0, we have reached the end of the script block.
                        if ($scriptBlockDepth -eq 0)
                        {
                            $scriptBlockFound = $false
                        }

                        continue
                    }

                    if ($currentToken.Kind -eq [System.Management.Automation.Language.TokenKind]::Variable)
                    {
                        # *******
                        # STEP 4.1: Find automatic variables that are used with the wrong casing.
                        # *******

                        $automaticVariable = $automaticVariableNames | Where-Object {
                            $PSItem.ToLowerInvariant() -eq $currentToken.Name.ToLowerInvariant() } | Select-Object -First 1

                        if ($null -ne $automaticVariable -and -not $automaticVariable.Equals($currentToken.Name, 'InvariantCulture'))
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $currentToken.Extent
                                'Message' = @(
                                    "Automatic variables should be used with the correct casing: '$automaticVariable'"
                                    "instead of '$($currentToken.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectAutomaticVariableNameCasing'
                                'RuleSuppressionID' = 'PSUseCorrectAutomaticVariableNameCasing'
                                'Severity' = 'Warning'
                            }

                            continue
                        }

                        # *******
                        # STEP 4.2: Find parameters that are used with the wrong casing.
                        # *******

                        if ($parameterNames.Length -gt 0)
                        {
                            $parameter = $parameterNames | Where-Object {
                                $PSItem.ToLowerInvariant() -eq $currentToken.Name.ToLowerInvariant() } | Select-Object -First 1

                            if ($null -ne $parameter -and -not $parameter.Equals($currentToken.Name, 'InvariantCulture'))
                            {
                                $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                    'Extent' = $currentToken.Extent
                                    'Message' = @(
                                        "Parameters should be used with the declared casing: '$parameter' instead of"
                                        "'$($currentToken.Name)'."
                                    ) -join ' '
                                    'RuleName' = 'PSUseParameterNameDeclaredCasing'
                                    'RuleSuppressionID' = 'PSUseParameterNameDeclaredCasing'
                                    'Severity' = 'Warning'
                                }

                                continue
                            }
                        }

                        # *******
                        # STEP 4.3: Find variables that are used with the wrong casing.
                        # *******

                        if ($false -and $currentToken.Name -NotMatch '(?-i)^[a-z][a-zA-Z0-9]*')
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $currentToken.Extent
                                'Message' = @(
                                    'Variable names should contain only alphanumeric characters and start with a'
                                    "lowercase letter: '$($currentToken.Name)'."
                                ) -join ' '
                                'RuleName' = 'PSUseCorrectVariableNameCasing'
                                'RuleSuppressionID' = 'PSUseCorrectVariableNameCasing'
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
