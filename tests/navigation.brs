sub main()
    Assert(NavBack(true, true, 2, "Movies") = "dialog", "dialog dismisses first")
    Assert(NavBack(false, true, 2, "Movies") = "player", "player returns to library")
    Assert(NavBack(false, false, 2, "TV Shows") = "stack", "detail goes to parent")
    Assert(NavBack(false, false, 0, "Movies") = "home", "root screen returns home")
    Assert(NavBack(false, false, 0, "Home") = "exit", "exit is intentional")
    choices = []
    for i = 1 to 1000
        choices.push("Category " + i.toStr())
    end for
    page = ChoicePage(choices, 2)
    Assert(page.items.count() = 6, "category picker is bounded")
    Assert(page.items[0] = "Category 13", "category page preserves order")
    Assert(page.hasPrevious and page.hasNext, "middle category page has both directions")
    last = ChoicePage(choices, 166)
    Assert(last.items.count() = 4 and not last.hasNext, "last category page retains remainder")
    print "PASS navigation 9"
end sub

sub Assert(value as boolean, label as string)
    if not value then
        print "FAIL " + label
        stop
    end if
end sub
