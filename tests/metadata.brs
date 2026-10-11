sub Main()
    m.failures = 0
    ApiResetMemory()
    m.auth = {authorization:"Bearer fixture-token", profile:"17", expires:0}
    item = {id:"movie-one", kind:"movie", imdbId:"tt0000001", title:"Provider title", artwork:"", description:"", url:"https://stream.example.test/one"}
    ApiIndex([item])
    m.httpResponses = [
        {path:"/api/info/movie/tt0000001", data:[{imdb_id:"tt0000001", title:"Canonical title", meta:{plot:"Canonical description"}}]}
        {path:"/api/info/movie/tt0000001", data:[{imdb_id:"tt0000001", title:"Canonical title", meta:{plot:"Canonical description", fanart:"https://images.example.test/one.jpg"}}]}
    ]
    m.httpCalls = 0
    first = CorePublicItem(item)
    ApiEnrich([first], "movie")
    Check(first.title = "Canonical title", "title-only response still enriches the title")
    Check(first.artwork = "", "title-only response preserves missing artwork")
    second = CorePublicItem(item)
    ApiEnrich([second], "movie")
    Check(second.artwork = "https://images.example.test/one.jpg", "title-only metadata stays retryable so later artwork reaches the catalog")
    Check(m.lookup["movie-one"].artwork = "https://images.example.test/one.jpg", "recovered artwork reaches saved catalog lookup")
    third = CorePublicItem(item)
    ApiEnrich([third], "movie")
    Check(third.artwork = "https://images.example.test/one.jpg", "complete metadata is served from the cache")
    Check(m.httpCalls = 2, "complete metadata does not repeat the detail request")
    ApiResetMemory()
    m.auth = {authorization:"Bearer fixture-token", profile:"17", expires:0}
    m.httpCalls = 0
    missing = {id:"movie-missing", kind:"movie", imdbId:"tt0000002", title:"Playlist-only title", artwork:"", description:""}
    m.httpResponses = [
        {path:"/api/info/movie/tt0000002", data:[]}
        {path:"/api/info/movie/tt0000002", data:[]}
    ]
    ApiEnrich([missing], "movie")
    ApiEnrich([missing], "movie")
    ApiEnrich([missing], "movie")
    Check(m.httpCalls = 2, "metadata absent from two successful replies is not requested on every browse")
    Check(missing.title = "Playlist-only title", "missing metadata never replaces an original provider title")
    ApiResetMemory()
    m.auth = {authorization:"Bearer fixture-token", profile:"17", expires:0}
    m.connected = true
    m.movies = [
        {id:"new", kind:"movie", imdbId:"tt0000002", title:"New playlist title", artwork:"", description:"", url:"https://stream.example.test/new"}
        {id:"known", kind:"movie", imdbId:"tt0000001", title:"Known playlist title", artwork:"", description:"", url:"https://stream.example.test/known"}
        {id:"edition", kind:"movie", imdbId:"tt0000001", title:"Known other edition", artwork:"", description:"", url:"https://stream.example.test/edition"}
        {id:"later", kind:"movie", imdbId:"tt0000003", title:"Later enriched title", artwork:"", description:"", url:"https://stream.example.test/later"}
    ]
    ApiIndex(m.movies)
    m.httpCalls = 0
    m.httpResponses = [
        {path:"/api/info/movie/categories", data:[{id:10, name:"Featured", is_genre:false, has_accessible_infos:true}]}
        {path:"/api/info/movie/items/10/0/250?use_lang_limits=0", data:{infos:[
            {imdb_id:"tt0000001", title:"Canonical known title", meta:{fanart:"https://images.example.test/known.jpg"}}
            {imdb_id:"tt9999999", title:"Not in this account playlist", meta:{fanart:"https://images.example.test/other.jpg"}}
        ]}}
        {path:"/api/info/movie/tt0000002,tt0000003", data:[{imdb_id:"tt0000003", title:"Later enriched title", meta:{fanart:"https://images.example.test/later.jpg"}}]}
        {path:"/api/info/movie/tt0000002", data:[]}
    ]
    catalog = ApiDispatch({id:1, op:"catalog", kind:"movie", page:0})
    Check(catalog.total = 4 and catalog.items.count() = 4, "browse backfill retains all playlist entries and excludes metadata-only titles")
    Check(catalog.items[0].id = "known", "browse begins with metadata-backed titles when new playlist IDs lack art")
    Check(catalog.items[0].artwork = "https://images.example.test/known.jpg", "category metadata supplies real artwork to the first browse card")
    Check(catalog.items[0].url = "https://stream.example.test/known", "browse reordering preserves the matched movie stream")
    Check(catalog.items[1].id = "edition" and catalog.items[1].url = "https://stream.example.test/edition", "multiple playlist editions remain separate playable items")
    Check(catalog.items[2].id = "new", "playlist-only titles remain available after illustrated titles")
    again = ApiDispatch({id:2, op:"catalog", kind:"movie", page:0})
    Check(again.items[2].id = "new" and again.items[3].id = "later", "later detail enrichment does not reorder pagination while browsing")
    ApiDispatch({id:3, op:"catalog", kind:"movie", page:0})
    Check(m.httpCalls = 4, "category warm-up runs once and absent detail IDs stop after two replies")
    ApiResetMemory()
    m.connected = true
    unavailable = ApiDispatch({id:4, op:"catalog", kind:"movie", page:0})
    Check(not unavailable.ok, "an unloaded unavailable movie catalog reports failure")
    Check(m.movies = invalid, "failed movie load retains its unloaded state so Retry can fetch again")
    TestBrowseRequestBounds()
    if m.failures = 0
        print "METADATA TESTS PASSED"
    else
        print "METADATA TESTS FAILED: "; m.failures
    end if
end sub

sub TestBrowseRequestBounds()
    ApiResetMemory()
    m.auth = {authorization:"Bearer fixture-token", profile:"17", expires:0}
    m.connected = true
    m.seriesPage = 1
    m.series = []
    records = []
    for i = 1 to 31
        imdbId = "tt" + i.toStr()
        m.series.push({id:"series-" + i.toStr(), kind:"series", imdbId:imdbId, title:"Show " + i.toStr(), artwork:"", description:"", episodes:[]})
        records.push({imdb_id:imdbId, title:"Show " + i.toStr(), meta:{fanart:"https://images.example.test/show.jpg"}})
    end for
    ApiIndex(m.series)
    m.httpCalls = 0
    m.httpResponses = [
        {path:"/api/info/tvshow/categories", maxTimeout:3000, data:[{id:10, is_genre:false}, {id:20, is_genre:true}, {id:30, is_genre:false}]}
        {path:"/api/info/tvshow/items/10/0/250?use_lang_limits=0", maxTimeout:3000, version:"V3", data:{infos:records}}
    ]
    result = ApiDispatch({id:5, op:"catalog", kind:"series", page:0})
    Check(result.total = 31 and result.items.count() = 30, "TV browse backfill preserves total inventory and bounded render pages")
    Check(result.items[0].artwork = "https://images.example.test/show.jpg", "TV category artwork reaches the browse cards")
    Check(m.httpCalls = 2, "warm-up stops after enough matched illustrated titles for one browse page")

    ApiResetMemory()
    m.auth = {authorization:"Bearer fixture-token", profile:"17", expires:0}
    m.connected = true
    m.movies = [{id:"new", kind:"movie", imdbId:"tt0000002", title:"New title", artwork:"", description:""}]
    m.httpCalls = 0
    m.httpResponses = [
        {path:"/api/info/movie/categories", maxTimeout:3000, data:[{id:10, is_genre:false}, {id:20, is_genre:true}, {id:30, is_genre:false}]}
        {path:"/api/info/movie/items/10/0/250?use_lang_limits=0", maxTimeout:3000, data:{infos:[]}}
        {path:"/api/info/movie/items/20/0/250?use_lang_limits=0", maxTimeout:3000, data:{infos:[]}}
        {path:"/api/info/movie/tt0000002", data:[]}
    ]
    result = ApiDispatch({id:6, op:"catalog", kind:"movie", page:0})
    Check(result.items.count() = 1 and result.items[0].id = "new", "catalog still returns original titles when browse metadata has no matches")
    Check(m.httpCalls = 4, "warm-up checks no more than two category pages before returning usable inventory")
end sub

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    m.httpCalls += 1
    if m.httpResponses.count() = 0
        Check(false, "unexpected additional metadata request")
        return {ok:false, code:500, body:"", headers:{}}
    end if
    expected = m.httpResponses.shift()
    Check(url = "https://dev.testbyte.top" + expected.path, "metadata uses the provider detail route and requested IMDb ID")
    Check(method = "GET", "metadata detail requests use GET")
    Check(headers["X-API-PROFILE"] = "17", "metadata includes the authenticated profile")
    if expected.maxTimeout <> invalid then Check(timeout <= expected.maxTimeout, "optional browse metadata requests have a short deadline")
    if expected.version <> invalid then Check(headers["X-API-Version"] = expected.version, "TV browse metadata uses the category API version")
    return {ok:true, code:200, body:formatJson({data:expected.data}), headers:{}}
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: "; label
    end if
end sub
