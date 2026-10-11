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
    m.connected = true
    m.seriesId = ""
    m.kind = "movie"
    m.category = "All"
    m.query = ""
    m.page = 0
    m.displayRows = []
    m.footer = {text:""}
    m.featureTitle = {text:"Your night starts here"}
    m.featureDescription = {text:"Connect your Apollo account to browse your real library."}
    m.featureHint = {text:"Choose Settings to connect"}
    loadCatalog()
    Assert(m.featureTitle.text = "Loading your library", "restored account does not show a sign-in hero while loading")
    Assert(m.featureDescription.text = "Your account is saved. Getting your movies, shows and channels ready.", "loading explains that the account is retained")
    Assert(m.featureHint.text = "You can browse when the library is ready", "loading does not ask for another connection")
    m.displayRows = [{items:[{id:"movie-1"}]}]
    m.featureTitle.text = "Selected title"
    loadCatalog()
    Assert(m.featureTitle.text = "Selected title", "refreshing preserves an existing selected title")
    m.screen = "Settings"
    m.top = {dialog:invalid}
    m.playing = false
    m.rows = {rowItemFocused:[0,0]}
    m.displayRows = [{items:[{id:"movie-1", kind:"movie"}]}]
    m.hasMore = true
    for each key in ["play", "fastforward", "rewind", "replay"]
        m.api.request = {op:"unchanged"}
        handled = onKeyEvent(key, true)
        Assert(not handled and m.api.request.op = "unchanged", "Settings does not operate on a hidden catalog using " + key)
    end for
    m.screen = "TV Shows"
    m.heading = {text:"TV Shows"}
    m.query = "original show query"
    m.seriesId = ""
    m.season = invalid
    m.stack = []
    m.displayRows = [{items:[{id:"series-1", kind:"series", title:"Example Show"}]}]
    m.loading = false
    onItemSelected()
    Assert(m.query = "", "opening a show starts with an empty episode search")
    Assert(m.stack[0].query = "original show query", "show navigation saves its parent search")
    m.query = "episode query"
    loadCatalog()
    Assert(m.api.request.query = "episode query", "episode search reaches the worker")
    m.savedScreens = {}
    rememberScreen()
    Assert(m.savedScreens["TV Shows"].query = "original show query", "sidebar navigation remembers the parent library search while browsing episodes")
    returnBack()
    Assert(m.query = "original show query" and m.api.request.query = "original show query", "Back restores the parent search instead of the episode query")
    m.seriesId = ""
    m.kind = "movie"
    m.page = 3
    handleOption(5)
    Assert(m.api.request.refresh = true and m.api.request.page = 0, "Refresh requests fresh inventory from the first result page")
    m.seriesId = "series-1"
    handleOption(5)
    Assert(m.api.request.refresh = true and m.api.request.op = "episodes", "episode Refresh requests fresh inventory")
    m.displayRows = []
    m.nav = {setFocus:function(value as boolean) as boolean
        return true
    end function}
    dialog = {unobserveField:function(field as string) as boolean
        return true
    end function}
    m.top.dialog = dialog
    m.dialogKind = "search"
    m.activeId = 100
    m.loading = true
    m.lastRequest = {op:"catalog"}
    returnBack()
    Assert(m.activeId = 100 and m.loading, "closing a search overlay keeps its background catalog response active")
    m.top.dialog = dialog
    m.dialogKind = "details"
    m.activeId = 101
    m.loading = true
    m.lastRequest = {op:"resolve"}
    returnBack()
    Assert(m.activeId = -1 and not m.loading, "Back still cancels a pending playback request")
    m.screen = "Movies"
    m.kind = "movie"
    m.category = "Drama"
    m.query = "I Swear"
    m.page = 2
    m.stack = []
    oldMovie = {id:"old-movie",kind:"movie",title:"Previous movie"}
    m.selected = oldMovie
    m.items = [oldMovie]
    m.displayRows = [{items:[oldMovie]}]
    m.rows = {rowItemFocused:[0,5],content:{oldMovie:true}}
    m.savedScreens = {"TV Shows":{category:"Mystery",query:"Silo",page:1,focus:[0,4]}}
    m.feature = {visible:true}
    m.actions = {visible:false}
    m.featureArt = {uri:"https://images.example.test/old-movie.jpg"}
    m.featureTitle.text = "Previous movie"
    m.hasMore = true
    showScreen("TV Shows", true)
    Assert(m.items.count() = 0 and m.displayRows.count() = 0 and m.rows.content = invalid and m.selected = invalid, "changing sections clears the previous library before the new request completes")
    Assert(focusedItem() = invalid and not m.hasMore, "old titles and page controls cannot operate during a section change")
    Assert(m.featureTitle.text = "Loading your library" and m.featureArt.uri = "pkg:/images/logo.png", "new sections display a loading hero without previous artwork")
    Assert(m.api.request.kind = "series" and m.api.request.category = "Mystery" and m.api.request.query = "Silo" and m.api.request.page = 1, "section changes retain the destination's saved query category and page")
    Assert(m.restoreFocus[0] = 0 and m.restoreFocus[1] = 4, "section changes restore the destination's saved focus after loading")
    previous = m.savedScreens["Movies"]
    Assert(previous.query = "I Swear" and previous.category = "Drama" and previous.page = 2 and previous.focus[1] = 5, "section changes save the previous library state before clearing its rows")
    tv = {id:"current-show",kind:"series",title:"Current show"}
    m.selected = tv
    m.items = [tv]
    m.displayRows = [{items:[tv]}]
    m.rows.content = {currentShow:true}
    m.featureTitle.text = "Current show"
    handleOption(5)
    Assert(m.api.request.refresh and m.selected.id = "current-show" and m.items.count() = 1 and m.displayRows.count() = 1 and m.rows.content.currentShow, "same-section Refresh keeps its selected visible content while loading")
    m.seriesId = ""
    m.season = invalid
    m.rows.rowItemFocused = [0,1]
    m.displayRows = [{items:[{id:"show-a",kind:"series",title:"Show A"},{id:"show-b",kind:"series",title:"Show B"}]}]
    m.restoreFocus = [0,1]
    m.loading = false
    onItemSelected()
    Assert(m.restoreFocus[0] = 0 and m.restoreFocus[1] = 0, "opening a show starts at its first episode instead of inheriting the parent column")
    m.choiceKind = "season"
    m.seasons = [1,2]
    m.choiceOffset = 0
    m.choiceCount = 2
    m.choicePrevious = -1
    m.choiceNext = -1
    m.rows.rowItemFocused = [0,3]
    m.restoreFocus = [0,3]
    handleChoice(1)
    Assert(m.restoreFocus[0] = 0 and m.restoreFocus[1] = 0 and m.api.request.season = 2 and m.api.request.page = 0, "changing seasons starts at the first episode on the first page")
    returnBack()
    Assert(m.restoreFocus[0] = 0 and m.restoreFocus[1] = 1, "Back from episodes retains the original selected show column")
    m.rows.rowItemFocused = [0,1]
    m.loading = false
    onItemSelected()
    staleEpisode = {id:"stale-episode",kind:"episode",title:"Old episode"}
    m.items = [staleEpisode]
    m.displayRows = [{items:[staleEpisode]}]
    m.selected = staleEpisode
    m.rows.content = {oldEpisodes:true}
    m.rows.rowItemFocused = [0,0]
    showScreen("TV Shows", true)
    Assert(m.seriesId = "" and m.stack.count() = 0 and m.items.count() = 0 and m.displayRows.count() = 0 and m.rows.content = invalid, "returning from episodes through the same sidebar section clears its child content")
    requestId = m.api.request.id
    onKeyEvent("play", true)
    Assert(m.api.request.id = requestId and m.api.request.op = "catalog" and m.selected = invalid, "Play cannot resolve a stale episode while the parent library reloads")
    Assert(m.api.request.query = "Silo" and m.restoreFocus[1] = 1, "same-section sidebar return restores the saved parent query and focus")
    m.displayRows = [{items:[oldMovie]}]
    m.rows.rowItemFocused = [0,0]
    m.selected = oldMovie
    m.loading = true
    m.api.request = {id:123,op:"catalog"}
    onKeyEvent("play", true)
    Assert(m.api.request.id = 123 and m.api.request.op = "catalog", "Play cannot replace a pending catalog request using rows that remain visible")
    m.displayRows = [{items:[{id:"show-a",kind:"series",title:"Show A"}]}]
    m.loading = true
    m.api.request = {id:124,op:"episodes"}
    depth = m.stack.count()
    onItemSelected()
    Assert(m.api.request.id = 124 and m.stack.count() = depth, "OK cannot duplicate child navigation while its episodes are still loading")
    m.loading = false
    Assert(focusedItem().id = "show-a", "focused content becomes selectable again after loading finishes")
    m.seriesId = ""
    m.kind = "movie"
    Assert(refreshOptionLabel() = "Refresh", "movie Refresh retains its whole-playlist label")
    m.kind = "series"
    Assert(refreshOptionLabel() = "Refresh first TV page", "TV catalog Refresh discloses its first-page limit")
    m.kind = "all"
    Assert(refreshOptionLabel() = "Refresh movies/live and first TV page", "mixed Search Refresh discloses its TV page limit without excluding movies or live")
    m.seriesId = "series-from-search"
    Assert(refreshOptionLabel() = "Refresh this show's first TV page", "episode Refresh describes the show's first page even when opened from Search")
    m.seriesId = ""
    m.kind = "live"
    Assert(refreshOptionLabel() = "Refresh", "leaving episode browsing clears the bounded-show Refresh label")
    Assert(detailMessage({description:invalid}) = "Details are not provided for this title.", "missing provider description is safe for the typed native details dialog")
    Assert(detailMessage({description:"  "}) = "Details are not provided for this title.", "blank provider description uses the same safe fallback")
    Assert(detailMessage({description:"A real synopsis"}) = "A real synopsis", "provider descriptions remain visible")
    print "PASS scene 52"
end sub

sub Assert(value as boolean, label as string)
    if not value then
        print "FAIL " + label
        stop
    end if
end sub
