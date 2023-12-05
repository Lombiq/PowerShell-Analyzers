# Lombiq PowerShell Analyzers

[![Lombiq.Analyzers.PowerShell NuGet](https://img.shields.io/nuget/v/Lombiq.Analyzers.PowerShell?label=Lombiq.Analyzers.PowerShell)](https://www.nuget.org/packages/Lombiq.Analyzers.PowerShell/)

## About

PowerShell static code analysis via [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) and [Lombiq's recommended configuration for it](Lombiq.Analyzers.PowerShell/PSScriptAnalyzerSettings.psd1). Use it from the CLI, in GitHub Actions, or integrated into MSBuild builds. Demo video [here](https://www.youtube.com/watch?v=GqUvneHxZ8g).

Looking for .NET static code analysis? Check out our [.NET Analyzers project](https://github.com/Lombiq/.NET-Analyzers).

Do you want to quickly try out this project and see it in action? Check it out in our [Open-Source Orchard Core Extensions](https://github.com/Lombiq/Open-Source-Orchard-Core-Extensions) full Orchard Core solution and also see our other useful Orchard Core-related open-source projects!

## Documentation

### Pre-requisites

- You must have [PowerShell 7 or greater installed](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell).
- The _PSScriptAnalyzer_ module must be installed. The script will attempt to auto-install it, however if this fails (e.g. on Windows PowerShell you have to be admin to install modules) follow the steps [here](https://docs.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules#installing-psscriptanalyzer).

Note that if you are using this in GitHub Actions, the common images (`windows-latest` and `ubuntu-latest`) already have these so you don't need to install anything.

### Usage

#### PowerShell CLI

Use the script like this to output the analyzer violations with `Write-Error`:

```pwsh
./Invoke-Analyzer.ps1 -SettingsPath PSScriptAnalyzerSettings.psd1
```

The `-SettingsPath` can be omitted, in this case the _PSScriptAnalyzerSettings.psd1_ in the same directory as the _Invoke-Analyzer.ps1_ will be used.

#### GitHub Actions

There are a few different ways to execute PowerShell static code analysis using GitHub Actions:

##### PowerShell Analyzers is a submodule of your repository

You can invoke it from an _action.yml_ file like this:

```yaml
    - name: Analyze PowerShell scripts
      shell: powershell # Run analysis from Windows PowerShell.
      run: <path-to-submodule>/Lombiq.Analyzers.PowerShell/Invoke-Analyzer.ps1 -ForGitHubAction
    - name: Analyze PowerShell scripts
      shell: pwsh # Run analysis from PowerShell Core.
      run: <path-to-submodule>/Lombiq.Analyzers.PowerShell/Invoke-Analyzer.ps1 -ForGitHubAction
```

The `-ForGitHubAction` switch enables displaying the results using [error workflow commands](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message). These create file annotations pointing to the exact script path and line number provided by PSScriptAnalyzer. You can review the results in the workflow summary page. If the violating files aren't in a submodule then they will be marked in the related pull request's Files tab as well.

##### Adding the reusable action to a workflow

See the [action](.github/actions/static-code-analysis/action.yml)'s parameters for configuration options. Example:

```yaml
    - name: PowerShell Static Code Analysis
      uses: Lombiq/PowerShell-Analyzers/.github/actions/static-code-analysis@dev
```

##### Calling the reusable workflow directly

See the [workflow](.github/workflows/static-code-analysis.yml), which is a wrapper for the action above, and its parameters for configuration options. Example:

```yaml
  powershell-static-code-analysis:
    uses: Lombiq/PowerShell-Analyzers/.github/workflows/static-code-analysis.yml@dev
```

#### MSBuild

This way you associate the analyzer with a .NET project and MSBuild automatically invokes analysis before building. If the analysis passes, it creates a timestamp and won't perform the analysis again until a new script file has been added or an existing one modified.

If this project is included via a submodule, edit the _csproj_ file of your primary project(s) and add the following:

```xml
<Import Project="path\to\Lombiq.Analyzers.PowerShell\Lombiq.Analyzers.PowerShell.targets" />
```

You don't need to `<ProjectReference>` _Lombiq.Analyzers.PowerShell.csproj_.

If you include the project as a NuGet package, it will work as-is.

Additionally, you can set these properties in the importing project's `<PropertyGroup>`:

- `<PowerShellAnalyzersRootDirectory>`: The analysis root directory, only files recursively found here are checked. If not specified, it uses the solution directory if present (if you are building the whole solution), otherwise the project directory (if you are building just the project).
- `<PowerShellAnalyzersArguments>`: Set it to customize the arguments passed to the script. This is useful if you want to provide your own rules configuration by setting it to `-ForMsBuild -SettingsPath path/to/settings.psd1`. If not specified, its value is `-ForMsBuild` unless a GitHub Actions environment is detected (via the `$GITHUB_ENV` variable) in which case the default value is `-ForGitHubAction`.

#### Visual Studio Code

Live analysis is outside of the scope of this project, however you can use the Visual Studio Code extension:

1. Install it from the [Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell).
2. Go to Settings and paste `powershell.scriptAnalysis.settingsPath` into the search bar.
3. Set it to the path of the _PSScriptAnalyzerSettings.psd1_ file to use our settings.

### Suppressing PSScriptAnalyzer rules

Occasionally there is good reason to ignore an analyzer warning. In this case add the `[Diagnostics.CodeAnalysis.SuppressMessage('PSCategoryId', 'ParameterName', Justification = 'Explain why.')]` attribute to the cmdlet's `param()` block. The first two parameters are mandatory:

1. `PSCategoryId` is an example for the Id of the analyzer rule and it usually starts with _PS_.
2. `ParameterName` is an example for the name of the parameter (notice that it doesn't start with `$`). Leave it empty if the suppression is not specific to a parameter.

For more information, see the module's [documentation](https://docs.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules#suppressing-rules).

Suppressing a specific line or range (like `#pragma warning disable` in C#) is not currently supported. See [the associated PSScriptAnalyzer issue](https://github.com/PowerShell/PSScriptAnalyzer/issues/849).

### Implementing custom analyzer rules

Check out [the official documentation](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/create-custom-rule) for instructions and [CommunityAnalyzerRules](https://github.com/PowerShell/PSScriptAnalyzer/blob/master/Tests/Engine/CommunityAnalyzerRules/CommunityAnalyzerRules.psm1) for additional inspiration. Custom rule modules should be placed in the `Lombiq.Analyzers.PowerShell\Rules` folder to be automatically detected by the `Invoke-Analyzer` script.

## Contributing and support

Bug reports, feature requests, comments, questions, code contributions and love letters are warmly welcome. You can send them to us via GitHub issues and pull requests. Please adhere to our [open-source guidelines](https://lombiq.com/open-source-guidelines) while doing so.

This project is developed by [Lombiq Technologies](https://lombiq.com/). Commercial-grade support is available through Lombiq.
