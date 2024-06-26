<#
.SYNOPSIS
    Detects the usages of the backtick (line continuation) character.
.DESCRIPTION
    In general, the community feels you should avoid using those backticks as "line continuation characters" when
    possible. They are hard to read, and easy to miss and mistype. Also, adding an extra whitespace after the backtick
    breaks the command execution. To fix a violation of this rule, please remove backticks from your script and use
    parameter splatting instead. You can run "Get-Help about_splatting" to get more details. Produces warnings of type
    'PSAvoidUsingLineContinuation'.
.EXAMPLE
    Measure-LineContinuation -Token $Token
.INPUTS
    [System.Management.Automation.Language.Token[]]
.OUTPUTS
    [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
.NOTES
    Copied (and improved) version of
    https://github.com/PowerShell/PSScriptAnalyzer/blob/master/Tests/Engine/CommunityAnalyzerRules/CommunityAnalyzerRules.psm1#L613.
#>
function Measure-LineContinuation
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

        try
        {
            foreach ($lineContinuationToken in $Token | Where-Object {
                    $PSItem.Kind -eq [System.Management.Automation.Language.TokenKind]::LineContinuation })
            {
                $results += [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                    'Extent' = $lineContinuationToken.Extent
                    'Message' = @(
                        'Using backtick (line continuation) makes the code harder to read and maintain. Please use'
                        'parameter splatting instead.'
                    ) -join ' '
                    'RuleName' = 'PSAvoidUsingLineContinuation'
                    'RuleSuppressionID' = 'PSAvoidUsingLineContinuation'
                    'Severity' = 'Warning'
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