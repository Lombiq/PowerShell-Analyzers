using namespace System.Management.Automation.Language

# Traverse the chain of parents of an AST object until a parent of a specific type is found.
function Find-AstNearestParent
{
    param(
        [Parameter(Mandatory = $true)] [Ast] $AstObject,
        [Parameter(Mandatory = $true)] [Type] $ParentType
    )

    $parent = $AstObject.Parent
    while ($null -ne $parent -and $parent -isNot $ParentType)
    {
        $parent = $parent.Parent
    }

    return $parent
}

# Traverse the chain of parents of an AST object to extract each parent of a specific type.
function Find-AstParent
{
    param(
        [Parameter(Mandatory = $true)] [Ast] $AstObject,
        [Parameter(Mandatory = $true)] [Type] $ParentType
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

# Extract the parameters of a script block or a function definition.
function Find-AstParameter
{
    param([Parameter(Mandatory = $true)] [Ast] $AstObject)

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
