sub Main()
    m.failures = 0
    m.httpCalls = 0
    ApiResetMemory()
    m.connected = true
    episodes = []
    for episode = 1 to 34
        episodes.push({id:"s1e" + episode.toStr(), kind:"episode", title:"Night " + episode.toStr(), category:"Drama", season:1, episode:episode, artwork:"", url:"https://media.example.test/episode.m3u8", format:"hls"})
    end for
    episodes.push({id:"s1e35", kind:"episode", title:"Daylight", category:"Drama", season:1, episode:35, artwork:""})
    episodes.push({id:"s2e1", kind:"episode", title:"Night Returns", category:"Drama", season:2, episode:1, artwork:""})
    show = {id:"series-one", kind:"series", title:"Fixture Series", category:"Drama", artwork:"https://images.example.test/series.jpg", episodes:episodes}
    ApiIndex([show])
    m.progress = {s1e31:{id:"s1e31", kind:"episode", position:120, duration:1000, updatedAt:1}}

    filtered = ApiDispatch({id:1, op:"episodes", seriesId:"series-one", season:1, query:"  NIGHT  ", page:1})
    Check(filtered.ok and filtered.connected, "episode search keeps the active account")
    Check(filtered.total = 34 and filtered.items.count() = 4, "search filters the selected season before applying the requested page")
    Check(filtered.page = 1 and not filtered.hasMore, "episode search reports the correct final page")
    if filtered.items.count() > 0
        Check(filtered.items[0].id = "s1e31", "episode search preserves episode ordering")
        Check(filtered.items[0].resumePosition = 120, "search results retain the saved resume position")
        Check(filtered.items[0].category = "Drama", "search results retain the provider category")
        Check(filtered.items[0].artwork = "https://images.example.test/series.jpg", "search results retain series artwork fallback")
    end if
    Check(filtered.seasons.count() = 2, "season choices remain available even when search filters episodes")
    Check(filtered.series.id = "series-one", "episode search retains the parent series")

    absent = ApiDispatch({id:2, op:"episodes", seriesId:"series-one", season:1, query:"No matching episode", page:0})
    Check(absent.ok and absent.total = 0 and absent.items.count() = 0, "unmatched episode query returns an empty successful result")
    cleared = ApiDispatch({id:3, op:"episodes", seriesId:"series-one", season:1, query:"", page:1})
    Check(cleared.total = 35 and cleared.items.count() = 5, "clearing search restores all episodes in the selected season")
    everySeason = ApiDispatch({id:4, op:"episodes", seriesId:"series-one", query:"night", page:1})
    Check(everySeason.total = 35 and everySeason.items.count() = 5, "query without a season searches all loaded episodes")
    Check(m.httpCalls = 0, "searching cached episodes makes no provider request")
    if m.failures = 0
        print "EPISODE TESTS PASSED"
    else
        print "EPISODE TESTS FAILED: "; m.failures
    end if
end sub

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    m.httpCalls += 1
    return {ok:false, code:503, body:"", headers:{}}
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: "; label
    end if
end sub
