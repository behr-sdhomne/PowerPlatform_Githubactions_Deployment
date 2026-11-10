param([Parameter(Mandatory)][string]$SolutionName)

$ErrorActionPreference = 'Stop'
if ($SolutionName -cnotmatch '\A[A-Za-z][A-Za-z0-9_]{0,64}\z' -or
    $SolutionName -match '\A(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])\z') {
    throw 'Solution unique name must be 1-65 ASCII letters, digits or underscores, start with a letter, and not be a reserved Windows filename.'
}
