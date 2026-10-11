sub Main()
    m.failures = 0
    ApiResetMemory()
    m.connected = true
    m.registry = PresentationRegistry()
    episode = {id:"episode-one",kind:"episode",title:"Current episode",description:"",artwork:"",url:"https://media.example.test/current.m3u8",format:"hls",headers:{"User-Agent":"Current Player"},seriesId:"series-one",season:2,episode:3,providerPage:4}
    show = {id:"series-one",kind:"series",title:"Current show",artwork:"https://images.example.test/show.jpg",episodes:[episode]}
    ApiIndex([show])
    browsed = ApiDispatch({id:1,op:"episodes",seriesId:"series-one",season:2})
    Check(browsed.items[0].artwork = "https://images.example.test/show.jpg", "episode browsing inherits its actual show artwork")
    requestItem = browsed.items[0]
    requestItem.url = "https://stale.example.test/old.m3u8"
    requestItem.headers = {"User-Agent":"Stale Player"}
    requestItem.format = "mp4"
    requestItem.providerPage = 19
    requestItem.title = "Outdated display title"
    resolved = ApiDispatch({id:2,op:"resolve",item:requestItem})
    Check(resolved.ok and resolved.item.artwork = "https://images.example.test/show.jpg", "resolving an episode retains safe artwork from its same-ID browse item")
    Check(resolved.item.url = "https://media.example.test/current.m3u8" and resolved.item.headers["User-Agent"] = "Current Player", "presentation fallback cannot replace current stream URL or headers")
    Check(resolved.item.format = "hls" and resolved.item.providerPage = 4, "current format and provider page remain authoritative")
    Check(resolved.item.title = "Current episode", "a nonempty current catalog title wins over the display copy")
    saved = ApiDispatch({id:3,op:"saveProgress",item:resolved.item,position:120,duration:1800})
    Check(saved.ok and m.progress["episode-one"].snapshot.artwork = "https://images.example.test/show.jpg", "resolved episode artwork survives into the persisted progress snapshot")
    Check(not m.progress["episode-one"].snapshot.doesExist("url") and not m.progress["episode-one"].snapshot.doesExist("headers"), "progress snapshot still excludes stream transport")
    history = ApiHistory(true)
    Check(history[0].artwork = "https://images.example.test/show.jpg", "history reuses snapshot artwork when the loaded episode lacks its own image")

    m.progress = {"movie-one":{id:"movie-one",kind:"movie",position:120,duration:1800,updatedAt:1,snapshot:{title:"Saved title",artwork:"https://images.example.test/saved.jpg",url:"https://stale.example.test/snapshot",headers:{"User-Agent":"Stale"},format:"mp4",providerPage:19}}}
    m.lookup = {"movie-one":{id:"movie-one",kind:"movie",title:"Fresh title",artwork:"",url:"https://media.example.test/fresh.m3u8",headers:{"User-Agent":"Fresh"},format:"hls",providerPage:2}}
    history = ApiHistory(false)
    Check(history[0].artwork = "https://images.example.test/saved.jpg" and history[0].title = "Fresh title", "fresh lookup keeps its title while filling missing history artwork")
    Check(history[0].url = "https://media.example.test/fresh.m3u8" and history[0].headers["User-Agent"] = "Fresh" and history[0].format = "hls" and history[0].providerPage = 2, "history presentation fallback leaves all current transport and page data intact")
    m.lookup["movie-one"].artwork = "https://images.example.test/current.jpg"
    resolved = ApiDispatch({id:4,op:"resolve",item:{id:"movie-one",artwork:"https://images.example.test/old.jpg"}})
    history = ApiHistory(false)
    Check(resolved.item.artwork = "https://images.example.test/current.jpg" and history[0].artwork = "https://images.example.test/current.jpg", "current artwork wins over display and saved artwork")
    m.lookup["movie-one"].artwork = ""
    m.progress["movie-one"].snapshot.artwork = "https://images.example.test/private.jpg?token=secret"
    resolved = ApiDispatch({id:5,op:"resolve",item:{id:"movie-one",artwork:"https://images.example.test/private.jpg?token=secret"}})
    history = ApiHistory(false)
    Check(resolved.item.artwork = "" and history[0].artwork = "", "credential-bearing artwork is rejected from both display and history fallbacks")
    missing = ApiDispatch({id:6,op:"resolve",item:{id:"removed",kind:"movie",artwork:"https://images.example.test/old.jpg",url:"https://stale.example.test/removed.m3u8",format:"hls"}})
    Check(not missing.ok, "safe presentation does not make an absent catalog item playable")
    if m.failures = 0 then print "PRESENTATION TESTS PASSED" else print "PRESENTATION TESTS FAILED: ";m.failures
end sub

function PresentationRegistry() as object
    return {
        write:function(key as string, value as string) as boolean
            return true
        end function
        flush:function() as boolean
            return true
        end function
    }
end function

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    Check(false, "presentation preservation needs no provider request")
    return {ok:false,code:503,body:"",headers:{}}
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: ";label
    end if
end sub
