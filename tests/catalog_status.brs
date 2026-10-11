sub Main()
    m.activeId = 42
    m.status = {text:""}
    m.api = {}
    m.screen = "Movies"
    m.category = "All"
    m.page = 1
    m.pickSeasonAfterLoad = false
    response = {id:42,op:"catalog",ok:true,items:[{id:"fixture"}],hasMore:true,complete:true,total:19592,scope:"Loaded provider titles and categories; canonical metadata appears as you browse.",message:""}
    m.api.response = response
    onApiResponse()
    Assert(len(m.status.text) < 70, "movie status leaves room for its actual result count")
    Assert(instr(1, m.status.text, "19592") > 0 and instr(1, m.status.text, "Page 2") > 0, "movie status retains the actual count and display page")

    m.screen = "TV Shows"
    response.total = 241
    response.complete = false
    response.scope = "TV provider pages loaded: 7 of up to 20. More shows and episodes may be available. Refreshed provider TV page 1; other loaded pages retained."
    m.api.response = response
    onApiResponse()
    Assert(len(m.status.text) < 70, "TV status stays readable after a refresh")
    Assert(instr(1, m.status.text, "TV pages 7/20") > 0, "TV status retains the loaded provider page limit")
    Assert(instr(1, m.status.text, "241") > 0, "TV status retains the matching title count")

    response.op = "episodes"
    response.total = 9
    response.scope = "Episodes from 3 loaded provider TV pages. Load more to check for other seasons."
    m.api.response = response
    onApiResponse()
    Assert(len(m.status.text) < 70 and instr(1, m.status.text, "TV pages 3") > 0, "episode status retains its limited provider scope without clipping")
    expectedStatus = m.status.text
    m.requestId = 0
    sendRequest({op:"resolve",item:{id:"fixture"}})
    Assert(m.status.text = expectedStatus, "starting playback does not replace the retained library status with endless loading")
    print "PASS catalog status"
end sub

' Native row rendering is outside this status-only boundary test.
sub renderRows()
end sub

sub Assert(value as boolean, label as string)
    if not value then
        print "FAIL " + label
        stop
    end if
end sub
