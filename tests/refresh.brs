sub Main()
    m.failures = 0
    m.calls = []
    m.responses = []
    ApiResetMemory()
    m.connected = true
    m.credentials = {kind:"apollo",username:"fixture",password:"fixture",baseUrl:"https://provider.example.test"}
    m.favorites = {keep:true}
    m.progress = {keep:{id:"keep",kind:"movie",position:30,updatedAt:1}}
    oldMovie = Playlist([Entry("movieone", "One", "movie-old"), Entry("removed", "Removed", "removed-old")])
    newMovie = Playlist([Entry("movieone", "One", "movie-new"), Entry("new", "New", "new")])
    m.movies = CoreParseM3U(oldMovie, "movie")
    ApiIndex(m.movies)
    movieId = m.movies[0].id
    removed = CorePublicItem(m.movies[1])
    Queue("movies", 503, "")
    failed = ApiDispatch({id:1,op:"catalog",kind:"movie",refresh:true})
    Check(not failed.ok and failed.connected, "failed movie refresh reports failure without signing out")
    Check(m.movies.count() = 2 and m.lookup[movieId].url = Media("movie-old"), "failed movie refresh retains inventory and index")
    Queue("movies", 200, newMovie)
    refreshed = ApiDispatch({id:2,op:"catalog",kind:"movie",refresh:true})
    Check(refreshed.ok and m.calls.count() = 2, "retry refresh refetches despite populated cache")
    Check(m.lookup[movieId].url = Media("movie-new"), "same movie identity receives its new URL")
    Check(not m.lookup.doesExist(removed.id), "removed movie is dropped from playback index")
    before = m.calls.count()
    stale = ApiDispatch({id:3,op:"resolve",item:removed})
    Check(not stale.ok and m.calls.count() = before, "removed movie cannot resolve or probe its stale URL")
    cached = ApiDispatch({id:4,op:"catalog",kind:"movie"})
    Check(cached.ok and m.calls.count() = before, "ordinary catalog access keeps its cache")

    m.live = CoreParseM3U(Playlist([Entry("liveone", "News", "live-old"), Entry("gone", "Gone", "gone")]), "live")
    ApiIndex(m.live)
    liveId = m.live[0].id
    removedLive = CorePublicItem(m.live[1])
    Queue("livetv", 200, "#EXTM3U")
    failed = ApiDispatch({id:5,op:"catalog",kind:"live",refresh:true})
    Check(not failed.ok and m.lookup[liveId].url = Media("live-old"), "empty live refresh keeps the previous usable cache")
    Queue("livetv", 200, Playlist([Entry("liveone", "News", "live-new")]))
    refreshed = ApiDispatch({id:6,op:"catalog",kind:"live",refresh:true})
    Check(refreshed.ok and m.live.count() = 1 and m.lookup[liveId].url = Media("live-new"), "live refresh replaces current channels")
    Check(not m.lookup.doesExist(removedLive.id), "removed live channel leaves index")
    before = m.calls.count()
    stale = ApiDispatch({id:7,op:"resolve",item:removedLive})
    Check(not stale.ok and m.calls.count() = before, "removed live channel cannot resolve its old URL")

    first = CoreParseM3U(Playlist([Entry("showone", "Show One S01 E01", "episode-old"), Entry("showremoved", "Removed Show S01 E01", "removed-episode")]), "episode")
    second = CoreParseM3U(Playlist([Entry("showtwo", "Show Two S02 E01", "page-two-old")]), "episode")
    for each episode in first
        episode.providerPage = 1
    end for
    second[0].providerPage = 2
    m.seriesRows = [first[0], first[1], second[0]]
    m.series = CoreBuildSeries(m.seriesRows)
    m.seriesPage = 2
    m.loadedSeriesPages = {"1":true,"2":true}
    ApiIndex(m.series)
    episodeId = first[0].id
    removedEpisode = CorePublicItem(first[1])
    removedShowId = first[1].seriesId
    pageTwoId = second[0].id
    pageTwoShowId = second[0].seriesId
    Queue("tvshows/1", 503, "")
    failed = ApiDispatch({id:8,op:"catalog",kind:"series",refresh:true})
    Check(not failed.ok and m.seriesRows.count() = 3 and m.loadedSeriesPages.count() = 2, "failed TV refresh leaves all loaded pages usable")
    Queue("tvshows/1", 200, Playlist([Entry("showone", "Show One S01 E01", "episode-new")]))
    refreshed = ApiDispatch({id:9,op:"catalog",kind:"series",refresh:true})
    Check(refreshed.ok and m.seriesRows.count() = 2 and m.loadedSeriesPages.count() = 2, "TV refresh replaces only provider page one")
    Check(m.lookup[episodeId].url = Media("episode-new") and m.lookup[pageTwoId].url = Media("page-two-old"), "TV refresh updates one page while retaining the other")
    Check(not m.lookup.doesExist(removedEpisode.id) and not m.lookup.doesExist(removedShowId), "removed episodes and shows leave the index")
    Check(instr(1, refreshed.scope, "page 1") > 0, "TV refresh states its bounded page scope")
    before = m.calls.count()
    stale = ApiDispatch({id:10,op:"resolve",item:removedEpisode})
    Check(not stale.ok and m.calls.count() = before, "removed episode cannot use its stale snapshot URL")

    Queue("tvshows/2", 503, "")
    failed = ApiDispatch({id:11,op:"episodes",seriesId:pageTwoShowId,refresh:true,season:2,query:"Two",page:0})
    Check(not failed.ok and m.lookup[pageTwoId].url = Media("page-two-old"), "failed episode refresh keeps the selected show usable")
    Queue("tvshows/2", 200, Playlist([Entry("showtwo", "Show Two S02 E01", "page-two-new"),Entry("showtwo", "Show Two S01 E02", "other-season")]))
    refreshed = ApiDispatch({id:12,op:"episodes",seriesId:pageTwoShowId,refresh:true,loadMore:true,season:2,query:"Two",page:0})
    Check(refreshed.ok and refreshed.total = 1 and refreshed.items.count() = 1, "episode refresh preserves query season and paging")
    Check(m.lookup[pageTwoId].url = Media("page-two-new") and m.lookup[episodeId].url = Media("episode-new"), "episode refresh replaces its show's first provider page only")
    Check(instr(1, refreshed.scope, "page 2") > 0, "episode refresh states the provider page refreshed")
    Check(m.credentials.username = "fixture" and m.connected and m.favorites.keep and m.progress.keep.position = 30, "refresh preserves account favorites and history")
    Check(m.responses.count() = 0 and m.calls.count() = 8, "each explicit refresh makes exactly one playlist request")
    ApiResetMemory()
    m.connected = true
    m.credentials = {kind:"apollo",username:"fixture",password:"fixture",baseUrl:"https://provider.example.test"}
    Queue("tvshows/1", 200, Playlist([Entry("showone", "Show One S01 E01", "first-page")]))
    initial = ApiDispatch({id:13,op:"catalog",kind:"series"})
    Queue("tvshows/2", 200, "#EXTM3U")
    ended = ApiDispatch({id:14,op:"catalog",kind:"series",loadMore:true})
    Check(ended.complete and m.seriesEndPage = 1, "empty next page learns the current provider catalog end")
    Queue("tvshows/1", 503, "")
    failed = ApiDispatch({id:15,op:"catalog",kind:"series",refresh:true})
    Check(not failed.ok and failed.complete and m.seriesEndPage = 1, "failed TV refresh retains the learned catalog end")
    Queue("tvshows/1", 200, Playlist([Entry("showone", "Show One S01 E01", "first-page-new")]))
    reopened = ApiDispatch({id:16,op:"catalog",kind:"series",refresh:true})
    Check(reopened.ok and not reopened.complete and reopened.canLoadMore and m.seriesEndPage = 20, "successful TV refresh permits discovering new provider pages")
    Queue("tvshows/2", 200, Playlist([Entry("newshow", "New Show S01 E01", "new-second-page")]))
    expanded = ApiDispatch({id:17,op:"catalog",kind:"series",loadMore:true})
    Check(expanded.ok and expanded.total = 2 and m.loadedSeriesPages.count() = 2, "Load more fetches a page that was empty before refresh")
    Check(m.responses.count() = 0 and m.calls.count() = 13, "end-of-catalog refresh and retry perform their expected requests")
    TestRefreshArtworkOrder()
    if m.failures = 0 then print "PASS refresh" else print "FAIL refresh assertions: "; m.failures
end sub

sub TestRefreshArtworkOrder()
    for each kind in ["movie", "series"]
        ApiResetMemory()
        m.connected = true
        m.credentials = {kind:"apollo",username:"fixture",password:"fixture",baseUrl:"https://provider.example.test"}
        m.calls = []
        m.responses = []
        path = "movies"
        suffix = ""
        if kind = "series"
            path = "tvshows/1"
            suffix = " S01 E01"
        end if
        old = Playlist([Entry("tt1001", "A New" + suffix, kind + "-new-old"), Entry("tt1002", "Z Known" + suffix, kind + "-known-old")])
        fresh = Playlist([Entry("tt1001", "A New" + suffix, kind + "-new-fresh"), Entry("tt1002", "Z Known" + suffix, kind + "-known-fresh")])
        if kind = "movie"
            m.movies = CoreParseM3U(old, "movie")
            ApiIndex(m.movies)
        else
            m.seriesRows = CoreParseM3U(old, "episode")
            for each episode in m.seriesRows
                episode.providerPage = 1
            end for
            m.series = CoreBuildSeries(m.seriesRows)
            m.seriesPage = 1
            m.loadedSeriesPages = {"1":true}
            ApiIndex(m.series)
        end if
        record = {imdb_id:"tt1002",title:"Z Known",meta:{fanart:"https://images.example.test/known.jpg"}}
        m.metadataBrowse[kind] = {attempts:1,complete:true,records:[record]}
        m.metadataAttempts[kind + ":tt1001"] = 2
        initial = ApiDispatch({id:18,op:"catalog",kind:kind,page:0})
        Check(initial.items[0].imdbId = "tt1002", "initial browsing puts matched artwork ahead of playlist-only entries")
        Queue(path, 503, "")
        failed = ApiDispatch({id:19,op:"catalog",kind:kind,page:0,refresh:true})
        Check(not failed.ok and failed.items[0].imdbId = "tt1002", "failed refresh preserves the current artwork order")
        Check(m.metadataBrowse[kind].preparedCount = 2, "failed refresh preserves the prepared ordering marker")
        Queue(path, 200, fresh)
        refreshed = ApiDispatch({id:20,op:"catalog",kind:kind,page:0,refresh:true})
        Check(refreshed.ok and refreshed.items[0].imdbId = "tt1002", "same-sized replacement rebuilds artwork order from cached metadata")
        known = m.lookup[refreshed.items[0].id]
        if kind = "movie" then url = known.url else url = known.episodes[0].url
        Check(url = Media(kind + "-known-fresh"), "reprioritized refreshed artwork keeps the corresponding fresh stream")
        Check(m.metadataBrowse[kind].attempts = 1 and m.metadataBrowse[kind].records.count() = 1, "refresh preserves cached browse metadata and its request budget")
        Check(m.metadataAttempts[kind + ":tt1001"] = 2, "refresh preserves detail retry budgets")
        Check(m.responses.count() = 0 and m.calls.count() = 2, "cached artwork reordering adds no metadata requests during refresh")
    end for
end sub

function Entry(providerId as string, title as string, path as string) as string
    return "#EXTINF:-1 tvg-id=" + chr(34) + providerId + chr(34) + " group-title=" + chr(34) + "Drama" + chr(34) + "," + title + chr(10) + Media(path)
end function

function Media(path as string) as string
    return "https://media.example.test/" + path + ".m3u8"
end function

function Playlist(entries as object) as string
    return "#EXTM3U" + chr(10) + entries.join(chr(10))
end function

sub Queue(path as string, code as integer, body as string)
    m.responses.push({path:path,ok:code >= 200 and code < 300,code:code,body:body,headers:{}})
end sub

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    m.calls.push(url)
    if m.responses.count() = 0
        Check(false, "unexpected HTTP request")
        return {ok:false,code:503,body:"",headers:{}}
    end if
    response = m.responses.shift()
    Check(url = "https://provider.example.test/api/list/fixture/fixture/m3u8/" + response.path and method = "GET", "refresh requests the expected real provider route")
    return response
end function

function TestUrlEncoder() as object
    return {escape:function(value as string) as string
        return value
    end function}
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: "; label
    end if
end sub
