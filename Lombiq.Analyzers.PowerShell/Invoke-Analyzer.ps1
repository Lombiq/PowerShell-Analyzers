[Diagnostics.CodeAnalysis.SuppressMessage(
    'PSReviewUnusedParameter',
    'ForGitHubActions',
    Justification = 'False positive due to https://github.com/PowerShell/PSScriptAnalyzer/issues/1472.')]
[Diagnostics.CodeAnalysis.SuppressMessage(
    'PSReviewUnusedParameter',
    'ForMsBuild',
    Justification = 'False positive due to https://github.com/PowerShell/PSScriptAnalyzer/issues/1472.')]
[Diagnostics.CodeAnalysis.SuppressMessage(
    'PSReviewUnusedParameter',
    'IncludeTestSolutions',
    Justification = 'False positive due to https://github.com/PowerShell/PSScriptAnalyzer/issues/1472.')]
param(
    $SettingsPath = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'PSScriptAnalyzerSettings.psd1'),
    [Switch] $ForGitHubActions,
    [Switch] $ForMsBuild,
    [Switch] $IncludeTestSolutions,
    [switch] $Fix
)

# This is like Get-ChildItem -Recurse -Include $IncludeFile | ? { $PSItem.FullName -NotLike "*\$ExcludeDirectory\*" }
# but much faster. For example, this is relevant for ignoring node_modules.
# - Measure-Command { Find-Recursively -Path . -IncludeFile *.ps1 -ExcludeDirectory node_modules } => 3.83s
# - Measure-Command { Get-ChildItem -Recurse -Force -Include $IncludeFile | ? { $PSItem.FullName -NotLike
#   "*\$ExcludeDirectory\*" } } => 111.27s
function Find-Recursively([string] $Path = '.', [string[]] $IncludeFile, [string] $ExcludeDirectory)
{
    $ExcludeDirectory = $ExcludeDirectory.ToUpperInvariant()

    function Find-Inner([System.IO.DirectoryInfo] $Here)
    {
        if ($Here.Name -like $ExcludeDirectory)
        {
            return
        }

        # The -Force switch is necessary to show hidden results, especially on Linux where entries starting with dot
        # are hidden by default.
        foreach ($child in (Get-ChildItem $Here.FullName -Force))
        {
            if ($child -is [System.IO.DirectoryInfo]) { Find-Inner $child }
            elseif (($IncludeFile | Where-Object { $child.name -like $PSItem }).Count) { $child }
        }
    }

    Find-Inner (Get-Item .)
}

function Write-FileError([string] $Message, [string] $Path, [int] $Line = 0, [int] $Column = 0)
{
    if ($Path) { $Path = Get-Item $Path }

    if ($ForGitHubActions)
    {
        $Message = $Message -replace '\s*(\r?\n\s*)+', ' '
        Write-Output "::error$(if ($Path) { " file=$Path,line=$Line,col=$Column::$Message" } else { "::$Message" })"
    }
    elseif ($ForMsBuild)
    {
        if (-not $Message.Contains(':')) { $Message = ": $Message" }

        if ($Path)
        {
            [Console]::Error.WriteLine("$Path($Line,$Column): error $Message")
        }
        else
        {
            [Console]::Error.WriteLine(": error $Message")
        }
    }
    else
    {
        Write-Error $(if ($Path) { "[$Path|ln ${Line}:${Column}] $Message" } else { $Message })
    }
}

if (Test-Path $SettingsPath)
{
    $SettingsPath = Get-Item $SettingsPath
}
else
{
    Write-FileError "The settings file `"$SettingsPath`" does not exist."
    exit -1
}

$installVersion = '1.21.0'
if ((Get-InstalledModule PSScriptAnalyzer -ErrorAction SilentlyContinue).Version -ne [Version]$installVersion)
{
    try
    {
        # Attempt to install it automatically. This will fail on Windows PowerShell because you have to be admin.
        Install-Module -Name PSScriptAnalyzer -Force -RequiredVersion $installVersion
    }
    catch
    {
        $infoUrl = 'https://docs.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules#installing-psscriptanalyzer'
        @(
            'Unable to detect Invoke-ScriptAnalyzer and failed to install PSScriptAnalyzer. If you are on Windows'
            'Powershell, open an administrator shell and type "Install-Module -Name PSScriptAnalyzer -RequiredVersion'
            "$installVersion`". Otherwise see $infoUrl to learn more."
        ) -join ' ' | Write-FileError
        exit -2
    }
}

$analyzerParameters = @{
    Settings = $SettingsPath.FullName
    CustomRulePath = Join-Path -Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -ChildPath Rules
    RecurseCustomRulePath = $true
    IncludeDefaultRules = $true
    Fix = $Fix
}
$results = Find-Recursively -IncludeFile '*.ps1', '*.psm1', '*.psd1' -ExcludeDirectory node_modules |
    Where-Object { # Exclude /TestSolutions/Violate-Analyzers.ps1 and /TestSolutions/*/Violate-Analyzers.ps1
        $IncludeTestSolutions -or -not (
            $PSItem.Name -eq 'Violate-Analyzers.ps1' -and
            ($PSItem.Directory.Name -eq 'TestSolutions' -or $PSItem.Directory.Parent.Name -eq 'TestSolutions')) } |
    ForEach-Object {
        $maxRetries = 3
        for ($retryCount = 0; $retryCount -lt $maxRetries; $retryCount++)
        {
            try
            {
                $extendedAnalyzerParameters = $analyzerParameters.Clone()
                $extendedAnalyzerParameters.Verbose = $retryCount -ge 1
                Invoke-ScriptAnalyzer -Path $PSItem.FullName @extendedAnalyzerParameters
                break
            }
            catch
            {
                if ($retryCount -eq ($maxRetries - 1))
                {
                    Write-Error "Failed to analyze $($PSItem.FullName) after $maxRetries attempts. Exception: $_"
                }
                else
                {
                    Write-Error "Retry #$($retryCount + 1): An exception occurred: $_. Retrying..."
                }
            }
        }
    }

foreach ($result in $results)
{
    $message = $result.RuleName + ': ' + $result.Message
    Write-FileError -Path $result.ScriptPath -Line $result.Line -Column $result.Column $message
}

# Exit code indicates the existence of analyzer violations instead of the number of violations, because exiting with
# code 5 (when there are 5 violations) changes how MSBuild interprets the results and yields the error MSB3075 instead
# of MSB3073 for some reason.
if ($results.Count -ne 0)
{
    exit 1
}
