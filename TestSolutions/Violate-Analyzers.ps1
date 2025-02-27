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

$hashtable = @{
    property1 = 'Lombiq'
    anotherProperty = 'Orchard'
}