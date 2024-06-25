function Violate-Analyzers($parameter = $LastExitCode, ${BracedParameter})
{
    $Message = 'This file contains intentionally bad code to verify that PSScriptAnalyzer works correctly.'
    if (!$Parameter) {
        Write-Host $message
    }
}

try { Violate-Analyzers } catch { }

"Lombiq", `
'Orchard', 'Hastlayer' | % { $_ }
