function NavBack(dialogOpen as boolean, playing as boolean, depth as integer, screen as string) as string
    if dialogOpen then return "dialog"
    if playing then return "player"
    if depth > 0 then return "stack"
    if screen <> "Home" then return "home"
    return "exit"
end function

function ChoicePage(choices as object, page as integer) as object
    if page < 0 then page = 0
    offset = page * 6
    selected = []
    for i = offset to offset + 5
        if i < choices.count() then selected.push(choices[i])
    end for
    return {items: selected, offset: offset, hasPrevious: page > 0, hasNext: offset + 6 < choices.count()}
end function
