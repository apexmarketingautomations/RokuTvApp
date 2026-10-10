sub main()
    m.requestId = 0
    m.api = {}
    m.status = {text:""}
    sendRequest({op:"login",username:"test-user",password:"synthetic-test-secret"})
    Assert(m.api.request.password = "synthetic-test-secret", "login is sent to worker")
    Assert(not m.lastRequest.doesExist("password"), "retry state must not retain password")
    Assert(not m.lastRequest.doesExist("username"), "retry state must not retain username")
    m.activeId = 21
    m.loading = true
    invalidateRequest()
    Assert(m.activeId = -1 and not m.loading, "Back invalidates pending resolve")
    m.selected = {url:"https://example.invalid/private-stream"}
    m.playItem = m.selected
    m.displayRows = [{items:[m.selected]}]
    m.lastRequest = {op:"resolve",item:m.selected}
    m.items = [m.selected]
    clearAccountView()
    Assert(m.selected = invalid and m.playItem = invalid, "signout releases selected stream")
    Assert(m.displayRows.count() = 0 and m.items.count() = 0, "signout drops row copies")
    Assert(m.lastRequest = invalid, "signout drops retry item")
    m.notice = {text:"",visible:false}
    m.api.response = {id:42,op:"saveProgress",ok:false,message:"Viewing progress could not be saved."}
    m.activeId = 99
    onApiResponse()
    Assert(m.notice.visible, "background persistence errors are visible")
    Assert(m.notice.text = "Viewing progress could not be saved.", "persistence error is understandable")
    m.api.request = {op:"none"}
    m.playing = true
    m.playbackStarted = false
    m.playItem = {id:"movie-1",kind:"movie",resumePosition:900}
    m.video = {position:0,duration:3600}
    savePlayback()
    Assert(m.api.request.op = "none", "failed startup does not erase resume")
    m.playbackStarted = true
    m.lastPlaybackPosition = 930
    m.lastPlaybackDuration = 3600
    savePlayback()
    Assert(m.api.request.position = 930, "save uses last valid rendered position")
    print "PASS scene 11"
end sub

sub Assert(value as boolean, label as string)
    if not value then
        print "FAIL " + label
        stop
    end if
end sub
