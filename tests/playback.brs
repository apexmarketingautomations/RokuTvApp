sub Main()
    ApiResetMemory()
    m.connected = true
    m.httpCalls = []
    m.streamUrl = "https://media.example.test/watch/123"
    m.lookup.movie = {id:"movie",kind:"movie",title:"Test movie",url:m.streamUrl,format:"",headers:{"User-Agent":"Provider Player"}}
    cases = [
        {mime:"application/vnd.apple.mpegurl", format:"hls"}
        {mime:"video/mp4", format:"mp4"}
        {mime:"application/dash+xml", format:"dash"}
        {mime:"video/x-matroska", format:"mkv"}
        {mime:"application/x-matroska", format:"mkv"}
        {mime:"video/x-matroska; charset=binary", format:"mkv"}
        {mime:"application/mp4", format:"mp4"}
        {mime:"video/quicktime", format:"mp4"}
    ]
    for each test in cases
        m.httpResponse = {ok:true,code:200,headers:{"Content-Type":test.mime},body:""}
        response = ApiResolve({item:{id:"movie"}}, {ok:true})
        Assert(response.ok, "extensionless " + test.mime + " reaches the player")
        Assert(response.item.format = test.format, "native format for " + test.mime)
        Assert(response.item.url = m.streamUrl, "resolver preserves the supplied stream URL")
        Assert(response.item.headers["User-Agent"] = "Provider Player", "resolver preserves provider playback headers")
        Assert(CoreFormat(m.streamUrl, test.mime) = test.format, "playlist MIME hint recognizes " + test.mime)
    end for
    Assert(m.httpCalls.count() = cases.count(), "known HEAD type needs only one request")
    for each call in m.httpCalls
        Assert(call.url = m.streamUrl and call.method = "HEAD", "probe uses the original URL and HEAD")
        Assert(call.headers["User-Agent"] = "Provider Player", "probe includes required provider headers")
    end for
    for each mime in ["application/json", "text/html", "application/octet-stream", "video/mp2t"]
        m.httpResponse = {ok:true,code:200,headers:{"content-type":mime},body:""}
        response = ApiResolve({item:{id:"movie"}}, {ok:true})
        Assert(not response.ok, "unrecognized or unsupported MIME does not invent a playable format")
    end for
    m.httpResponse = {ok:false,code:403,headers:{"Content-Type":"video/mp4"},body:""}
    response = ApiResolve({item:{id:"movie"}}, {ok:true})
    Assert(not response.ok, "unsuccessful probe does not infer format from failure body")

    ApiResetMemory()
    m.connected = true
    m.credentials = {kind:"m3u",playlistUrl:"https://provider.example.test/live.m3u8"}
    playlist = "#EXTM3U" + chr(10) + "#EXTINF:-1 tvg-id=" + chr(34) + "channel1" + chr(34) + ",News" + chr(10) + "https://media.example.test/live/1.m3u8"
    channel = CoreParseM3U(playlist, "live")[0]
    m.httpResponse = {ok:true,code:200,headers:{},body:playlist}
    m.httpCalls = []
    response = ApiResolve({item:{id:channel.id,kind:"live",title:"News"}}, {ok:true})
    Assert(response.ok, "restored live history reacquires current provider URL before playback")
    Assert(response.item.url = "https://media.example.test/live/1.m3u8", "history resolves current live catalog item")
    Assert(m.httpCalls.count() = 1, "live history fetches unloaded live inventory once")
    Assert(m.httpCalls[0].method = "GET", "live history reloads the provider playlist")
    print "PASS playback resolver"
end sub

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    m.httpCalls.push({url:url,method:method,headers:headers})
    return m.httpResponse
end function

sub Assert(value as boolean, label as string)
    if not value then
        print "FAIL " + label
        stop
    end if
end sub
