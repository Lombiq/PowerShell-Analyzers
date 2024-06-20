using namespace System.Management.Automation.Language

function Find-AstNearestParent
{
    param(
        [Ast] $AstObject,
        [Type] $ParentType
    )

    $parent = $AstObject.Parent
    while ($null -ne $parent -and $parent -isnot $ParentType)
    {
        $parent = $parent.Parent
    }

    return $parent
}

function Find-AstParents
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'This function can return multiple parents.')]
    param(
        [Ast] $AstObject,
        [Type] $ParentType
    )

    $parents = @()
    $currentParent = Find-AstNearestParent -AstObject $AstObject -ParentType $ParentType
    while ($null -ne $currentParent)
    {
        $parents += @($currentParent)
        $currentParent = Find-AstNearestParent -AstObject $currentParent -ParentType $ParentType
    }

    return $parents
}

function Find-AstParameters
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns',
        '',
        Justification = 'This function can return multiple parameters.')]
    param([Ast] $AstObject)

    $parameters = @()

    if (-not $AstObject -is [ScriptBlockAst] -and -not $AstObject -is [FunctionDefinitionAst])
    {
        throw 'The provided AST object is not a script block or a function definition.'
    }

    if ($AstObject.Parameters)
    {
        $parameters += $AstObject.Parameters
    }
    elseif ($AstObject.ParamBlock.Parameters)
    {
        $parameters += $AstObject.ParamBlock.Parameters
    }
    elseif ($AstObject.Body.ParamBlock.Parameters)
    {
        $parameters += $AstObject.Body.ParamBlock.Parameters
    }

    return $parameters
}
