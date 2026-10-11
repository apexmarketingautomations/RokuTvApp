sub Main()
    m.playing = false
    for each category in ["http", "drm", "mediaerror", "mediaplayer"]
        m.video = {state:"error",errorCode:-6,errorInfo:{category:category,errcode:-1004,drmerrcode:0,dbgmsg:"https://private.example.test/account/secret",source:"private-source"}}
        onVideoState()
    end for
    m.video = {state:"error",errorCode:-6,errorInfo:{category:"https://private.example.test/account/secret",errcode:"secret",drmerrcode:"secret",dbgmsg:"secret"}}
    onVideoState()
    m.video = {state:"playing",errorCode:0,errorInfo:invalid}
    onVideoState()
    m.video = {downloadedSegment:{Status:961,SegSequence:22,SegStart:176,SegType:2,BitrateBPS:7201340,Width:1920,Height:1036,SegUrl:"https://private.example.test/secret",Path:"secret",SegSize:0,DownloadDuration:400}}
    onDownloadedSegment()
    print "PASS player diagnostics"
end sub
