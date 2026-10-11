sub Main()
    m.failures = 0
    q = chr(34)
    fixture = "#EXTM3U" + chr(10)
    fixture += "#EXTINF:-1 tvg-id=" + q + "tt42" + q + " tvg-name=" + q + "PLANES, TRAINS" + q + " group-title=" + q + "Comedy, Classics" + q + ",Planes, Trains and Automobiles" + chr(10)
    fixture += "https://example.test/secret-user/secret-password/42.mp4" + chr(10)
    movies = CoreParseM3U(fixture, "movie")
    Check(movies.count() = 1, "quoted commas retain one playable movie")
    if movies.count() = 1
        Check(movies[0].title = "Planes, Trains and Automobiles", "display suffix is the title")
        Check(movies[0].category = "Comedy, Classics", "quoted category comma")
        Check(instr(1, movies[0].id, "secret") = 0, "persistent identity excludes credentials")
        Check(movies[0].format = "mp4", "movie format extension")
    end if
    replacement = fixture.replace("secret-password", "rotated-password")
    renamed = CoreParseM3U(replacement, "movie")
    if movies.count() = 1 and renamed.count() = 1
        Check(movies[0].id = renamed[0].id, "password rotation preserves identity")
    end if
    unknown = CoreParseM3U("#EXTINF:-1,Provider title" + chr(10) + "https://example.test/watch/1", "movie")
    Check(unknown.count() = 1, "unknown provider title remains playable")
    if unknown.count() = 1
        Check(unknown[0].title = "Provider title", "metadata absence preserves title")
        Check(unknown[0].format = "", "extensionless VOD is not assumed HLS")
    end if
    showRows = [
        {id:"e2", title:"River City S02 E03 Arrival", category:"Drama", url:"https://example.test/2", kind:"episode"}
        {id:"e1", title:"River City S01E02 Home", category:"Drama", url:"https://example.test/1", kind:"episode"}
        {id:"news", title:"Evening Report", category:"News", url:"https://example.test/3", kind:"episode"}
        {id:"other", title:"Morning Report", category:"News", url:"https://example.test/4", kind:"episode"}
    ]
    shows = CoreBuildSeries(showRows)
    Check(shows.count() = 3, "markerless titles do not collapse into genres")
    for each show in shows
        if show.title = "River City"
            Check(show.episodes.count() = 2, "explicit episode markers group series")
            Check(show.episodes[0].season = 1, "episodes sorted by numeric season")
            Check(show.episodes[0].episode = 2, "episode number preserved")
        end if
    end for
    rows = []
    for i = 1 to 70
        rows.push({id:i.toStr(), title:"Title " + i.toStr(), category:"Drama", kind:"movie"})
    end for
    first = CorePage(rows, "All", "", 0)
    third = CorePage(rows, "All", "", 2)
    Check(first.items.count() = 30, "render page is bounded")
    Check(first.total = 70, "total reflects filtered inventory")
    Check(first.hasMore, "first page reports more results")
    Check(third.items.count() = 10, "last page has remainder")
    Check(not third.hasMore, "last page terminates pagination")
    Check(CorePage(rows, "Comedy", "", 0).items.count() = 0, "category filter is applied")
    categoryRows = [
        {id:"oldest",kind:"movie",title:"Oldest",category:"Movies 1915"}
        {id:"old",kind:"movie",title:"Old",category:"Movies 1920"}
        {id:"new",kind:"movie",title:"New",category:"Movies 2026"}
        {id:"last",kind:"movie",title:"Last year",category:"Movies2025"}
        {id:"drama",kind:"movie",title:"Drama",category:"Drama"}
        {id:"action",kind:"movie",title:"Action",category:"Action"}
        {id:"collection",kind:"movie",title:"Collection",category:"Movies 2020 Classics"}
        {id:"news",kind:"live",title:"News",category:"News 2026"}
        {id:"new2",kind:"movie",title:"New again",category:"Movies 2026"}
    ]
    categories = CoreCategories(categoryRows)
    Check(categories.join("|") = "All|Movies 2026|Movies2025|Movies 1920|Movies 1915|Action|Drama|Movies 2020 Classics|News 2026", "real movie years are newest first, All stays first and other groups remain alphabetized")
    for each category in categories
        if category <> "All"
            filtered = CorePage(categoryRows, category, "", 0)
            Check(filtered.total > 0, "every category option retains a real filter value")
            for each filteredItem in filtered.items
                Check(filteredItem.category = category, "category ordering does not broaden or rename exact filters")
            end for
        end if
    end for
    Check(CorePage(categoryRows, categories[1], "", 0).total = 2, "first year choice reaches the newest movies and excludes older years")
    categoryRows.reverse()
    Check(CoreCategories(categoryRows).join("|") = categories.join("|"), "category ordering is independent of provider item order")
    item = {id:"movie42", kind:"movie", url:"https://example.test/secret", headers:{Authorization:"Bearer secret"}, title:"Secret must not persist"}
    progress = CoreProgress(item, 120, 1000, 1234)
    Check(progress.position = 120, "resume position retained")
    Check(not progress.doesExist("url"), "progress excludes URL")
    Check(not progress.doesExist("headers"), "progress excludes headers")
    Check(not progress.doesExist("url"), "progress never persists stream transport")
    if CoreAA(progress.snapshot)
        Check(not progress.snapshot.doesExist("url"), "history snapshot excludes stream URL")
        Check(not progress.snapshot.doesExist("headers"), "history snapshot excludes request headers")
    end if
    Check(CoreProgress(item, 990, 1000, 1234).position = 0, "completed item restarts")
    Check(CoreProgress(item, -10, 1000, 1234).position = 0, "negative seek is clamped")
    Check(not CoreValidSession({code:"123456", pollToken:"x"}), "incomplete pairing session rejected")
    Check(not CoreValidSession({code:"123456", pollToken:"x", setupUrl:"http://example.test/setup", expiresAt:9999999999999}), "insecure pairing URL rejected")
    Check(CoreValidSession({code:"123456", pollToken:"x", setupUrl:"https://example.test/setup", expiresAt:9999999999999}), "valid pairing session accepted")
    Check(CoreSafeArtwork("https://example.test/image.jpg?token=secret") = "", "credential-bearing artwork rejected")
    Check(CoreSafeArtwork("//example.test/image.jpg") = "https://example.test/image.jpg", "protocol relative artwork normalized")
    headerFixture = "#EXTINF:-1,Protected stream" + chr(10) + "#EXTVLCOPT:http-user-agent=Provider Player" + chr(10) + "#EXTVLCOPT:http-referrer=https://provider.test/" + chr(10) + "https://example.test/live.m3u8"
    protected = CoreParseM3U(headerFixture, "live")
    Check(protected[0].headers["User-Agent"] = "Provider Player", "VLC user agent is preserved")
    Check(protected[0].headers.Referer = "https://provider.test/", "VLC referrer is preserved")
    onlyShow = CorePage(shows, "All", "River", 0).items[0]
    Check(not onlyShow.doesExist("episodes"), "catalog response excludes unbounded episode trees")
    Check(ApiXmlDate("20260924060000 -0400") = 1790244000, "XMLTV negative offset converts to UTC")
    Check(ApiXmlDate("20260924120000 +0200") = 1790244000, "XMLTV positive offset converts to UTC")
    Check(ApiXmlDate("bad-date") = 0, "invalid XMLTV date is rejected")
    ApiResetMemory()
    m.connected = true
    m.live = rows
    ApiIndex(rows)
    m.progress = {"1":{id:"1",kind:"movie",position:120,duration:1000,updatedAt:2}, "2":{id:"2",kind:"movie",position:0,duration:1000,updatedAt:3}}
    m.favorites = {"1":true}
    response = ApiDispatch({id:17,op:"catalog",kind:"live",page:0})
    Check(response.id = 17, "worker echoes request identity")
    Check(response.items.count() = 30, "worker exposes a bounded catalog response")
    Check(response.recent.count() = 2, "history resolves against real current inventory")
    Check(response.recent[0].id = "2", "recent playback order follows watch time")
    Check(response.continue.count() = 1, "completed item is absent from continue watching")
    Check(response.continue[0].resumePosition = 120, "resume position reaches actual content")
    Check(response.items[0].favorite, "favorites decorate playable entries")
    m.seriesRows = showRows
    m.series = shows
    ApiIndex(shows)
    for each show in shows
        if show.title = "River City" then river = show
    end for
    episodes = ApiDispatch({id:18,op:"episodes",seriesId:river.id,season:1})
    Check(episodes.items.count() = 1, "worker season filter excludes other seasons")
    Check(episodes.items[0].id = "e1", "worker preserves real episode mapping")
    Check(not episodes.complete, "partial series inventory is reported honestly")
    remembered = CoreProgress({id:"episode-remembered",kind:"episode",title:"Actual watched episode",artwork:"https://images.test/still.jpg",seriesId:"series-remembered",providerPage:12,season:3,episode:7,url:"https://provider.test/private-password",headers:{Authorization:"secret"}}, 600, 2000, 99)
    m.progress = {"episode-remembered":remembered}
    m.lookup = {}
    resumed = ApiHistory(true)
    Check(resumed.count() = 1, "resume history survives restart before TV catalog load")
    if resumed.count() = 1
        Check(resumed[0].title = "Actual watched episode", "historical item retains genuine content title")
        Check(resumed[0].providerPage = 12, "episode history retains provider page for fresh resolution")
        Check(not resumed[0].doesExist("url"), "historical item has no stale private playback URL")
    end if
    ApiIndex(rows)
    remakes = CoreBuildSeries([
        {id:"old1",imdbId:"tt100",title:"The Bridge S01E01",category:"Drama",kind:"episode"}
        {id:"new1",imdbId:"tt200",title:"The Bridge S01E01",category:"Drama",kind:"episode"}
    ])
    Check(remakes.count() = 2, "explicit series IDs keep same-named remakes separate")
    unidentified = CoreBuildSeries([
        {id:"unknownA",title:"S01E01 Unrelated pilot",category:"Drama",kind:"episode"}
        {id:"unknownB",title:"S01E02 Another programme",category:"Drama",kind:"episode"}
    ])
    Check(unidentified.count() = 2, "genre group does not invent unknown series identity")
    pageOne = CoreParseM3U("#EXTINF:-1 tvg-id=" + q + "tt300" + q + " tvg-name=" + q + "Provider Series" + q + " group-title=" + q + "Drama" + q + ",Provider Series S01E01 Pilot" + chr(10) + "https://example.test/u/p/one", "episode")
    pageTwo = CoreParseM3U("#EXTINF:-1 tvg-id=" + q + "tt300" + q + " tvg-name=" + q + "Provider Series" + q + " group-title=" + q + "Drama" + q + ",Provider Series S01E02 Home" + chr(10) + "https://example.test/u/p/two", "episode")
    Check(pageOne[0].id <> pageTwo[0].id, "episode IDs are independent of playlist page duplicate numbering")
    mergedShow = CoreBuildSeries([pageOne[0], pageTwo[0]])
    Check(mergedShow.count() = 1, "shared explicit series ID groups episodes across pages")
    Check(mergedShow[0].episodes.count() = 2, "separate provider pages preserve both episodes")
    Check(not ApiDispatch({id:181,op:"episodes",seriesId:"1"}).ok, "nonseries episode request is rejected without crashing worker")
    Check(CoreNumber("17", -1) = 17, "numeric string profile IDs are normalized")
    Check(CoreNumber("17bad", -1) = -1, "malformed numeric profile IDs are rejected")
    m.lookup.mkv = {id:"mkv",kind:"movie",url:"https://example.test/video.mkv",format:"mkv"}
    m.lookup.transport = {id:"transport",kind:"live",url:"https://example.test/live.ts",format:"ts"}
    Check(ApiDispatch({id:19,op:"resolve",item:{id:"mkv"}}).ok, "documented MKV format reaches Roku player")
    Check(not ApiDispatch({id:20,op:"resolve",item:{id:"transport"}}).ok, "undocumented TS streamFormat is not passed to player")
    m.registry = TestRegistry(true)
    m.favorites = {}
    for i = 1 to 100
        m.favorites[i.toStr()] = true
    end for
    limited = ApiDispatch({id:21,op:"favorites",item:{id:"new-favorite"}})
    Check(not limited.ok, "favorites limit reports storage bound")
    Check(m.favorites.count() = 100, "favorites stay within registry budget")
    m.registry = TestRegistry(false)
    failedSave = ApiDispatch({id:22,op:"saveProgress",item:{id:"movie42",kind:"movie"},position:100,duration:1000})
    Check(not failedSave.ok, "registry failure is reported for resume save")
    failedFavorite = ApiDispatch({id:23,op:"favorites",item:{id:"1"}})
    Check(not failedFavorite.ok, "registry failure is reported for favorite change")
    failedSignout = ApiDispatch({id:24,op:"signout"})
    Check(not failedSignout.ok, "registry failure is reported for signout deletion")
    if m.failures = 0
        print "CORE TESTS PASSED"
    else
        print "CORE TESTS FAILED: "; m.failures
    end if
end sub

function TestRegistry(succeeds as boolean) as object
    return {
        succeeds:succeeds
        write:function(key as string, value as string) as boolean
            return m.succeeds
        end function
        flush:function() as boolean
            return m.succeeds
        end function
        delete:function(key as string) as boolean
            return m.succeeds
        end function
        exists:function(key as string) as boolean
            return true
        end function
    }
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: "; label
    end if
end sub
