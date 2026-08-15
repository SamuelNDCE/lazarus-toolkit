# DELIBERATELY BROKEN. Every checker must flag something here.
# A checker that reports this file clean is not working, and this file
# exists so that can be proven rather than assumed.
#
# It contains, on purpose:
#   1. a call to a function defined LATER in the file  (check-order)
#   2. a call to a function that does not exist at all (check-commands)
#   3. a variable assigned and never read               (audit)
#   4. a function defined twice                         (audit)
#   5. a hashtable keyed with the literal name "Keys"   (the trap itself)

Invoke-DefinedFurtherDown              # 1. used before it is defined
Invoke-NothingLikeThisExistsAnywhere   # 2. defined nowhere

$neverReadAgain = 'this value goes nowhere'   # 3. dead variable

function Invoke-DefinedFurtherDown {
    Write-Output 'defined below its own call site'
}

function Duplicated {                  # 4. first definition
    Write-Output 'first'
}
function Duplicated {                  # 4. second, silently wins
    Write-Output 'second'
}

# 5. The member-collision trap, so a checker can be tested against it.
$trap = @{}
$trap['Keys']  = 1
$trap['Count'] = 2
$trap['real']  = 3
