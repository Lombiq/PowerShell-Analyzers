<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
    Measure-VariableNameStyling -Token $Token
.INPUTS
    [System.Management.Automation.Language.Token[]]
.OUTPUTS
    [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>

function Measure-VariableNameStyling
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
                    # Find '(' tokens and increase the parenthesis depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::LParen)
                    {
                        $parenthesisDepth++

                        continue
                    }

                    # Find ')' tokens and decrease the parenthesis depth.
                    if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::RParen)
                    {
                        $parenthesisDepth--

                        # If the parenthesis depth reaches 0, we are done with the parameter list.
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

                        If the parameter name is not in the correct format, add a diagnostic record.
                        if ($token.Name -NotMatch '(?-i)^[A-Z][a-zA-Z0-9]*')
                        {
                            $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                                'Extent' = $token.Extent
                                'Message' = ('Parameter names should contain only alphanumeric characters and start' +
                                    " with an uppercase letter: $($token.Name).")
                                'RuleName' = 'PSUseCorrectParameterNameStyling'
                                'RuleSuppressionID' = 'PSUseCorrectParameterNameStyling'
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
