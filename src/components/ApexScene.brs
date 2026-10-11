sub init()
    m.top.backgroundColor = "0x050814FF"
    for each name in ["shell", "nav", "heading", "status", "feature", "featureArt", "featureTitle", "featureDescription", "featureHint", "featureEyebrow", "rows", "actions", "footer", "video", "notice", "startupTimer", "pairTimer", "saveTimer"]
        m[name] = m.top.findNode(name)
    end for
    m.screen = "Home"
    m.kind = "movie"
    m.category = "All"
    m.query = ""
    m.page = 0
    m.stack = []
    m.savedScreens = {}
    m.items = []
    m.displayRows = []
    m.categories = ["All"]
    m.seasons = []
    m.seriesId = ""
    m.focusAfterLoad = false
    m.requestId = 0
    m.activeId = 0
    m.connected = false
    m.loading = false
    m.playing = false
    m.hasMore = false
    m.complete = false
    m.dialogKind = ""
    m.relay = "https://pairing-service-production.up.railway.app"
    m.navNames = ["Home", "Movies", "TV Shows", "Live TV", "Favorites", "Guide", "Search", "Settings"]
    m.nav.content = makeList(m.navNames)
    m.nav.observeField("itemSelected", "onNavSelected")
    m.rows.observeField("rowItemSelected", "onItemSelected")
    m.rows.observeField("rowItemFocused", "onItemFocused")
    m.actions.observeField("itemSelected", "onActionSelected")
    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onVideoPosition")
    m.video.observeField("downloadedSegment", "onDownloadedSegment")
    m.startupTimer.observeField("fire", "onStartupTimeout")
    m.pairTimer.observeField("fire", "onPairTimer")
    m.saveTimer.observeField("fire", "savePlayback")
    m.api = CreateObject("roSGNode", "ApiTask")
    m.api.observeField("response", "onApiResponse")
    m.api.control = "RUN"
    m.nav.setFocus(true)
    sendRequest({op: "restore", relayUrl: m.relay})
    info = CreateObject("roDeviceInfo")
    ui = info.GetUIResolution()
    m.deviceSummary = info.GetModel() + " / UI " + ui.width.toStr() + " x " + ui.height.toStr()
    telemetry({event: "launch", build: "1.0.00006", model: info.GetModel(), ui_width: ui.width, ui_height: ui.height})
end sub

function makeList(names as object) as object
    root = CreateObject("roSGNode", "ContentNode")
    for each name in names
        node = root.createChild("ContentNode")
        node.title = name
    end for
    return root
end function

sub telemetry(data as object)
    print "APEX_EVENT " + FormatJson(data)
end sub

sub sendRequest(req as object, foreground = true as boolean)
    m.requestId++
    req.id = m.requestId
    if foreground then
        m.activeId = req.id
        m.loading = true
        retry = {}
        retry.append(req)
        for each secret in ["username", "password", "provisioningToken", "session"]
            retry.delete(secret)
        end for
        m.lastRequest = retry
        if req.op <> "resolve" then m.status.text = "Loading your library..."
    end if
    m.api.request = req
end sub

sub onApiResponse()
    r = m.api.response
    if r = invalid then return
    if r.op = "saveProgress" then
        if not r.ok then
            m.notice.text = r.message
            m.notice.visible = true
        end if
        return
    end if
    if r.id <> m.activeId then return
    m.loading = false
    if r.connected <> invalid then m.connected = r.connected
    if not r.ok then
        m.status.text = r.message
        showDialog("Unable to continue", r.message, ["Try again", "Connection settings", "Back"], "requestError")
        return
    end if
    if r.op = "restore" or r.op = "login" then
        if m.connected then
            showScreen("Home", false)
        else
            showScreen("Settings", false)
            m.status.text = "Connect with your Apollo username and password."
        end if
    else if r.op = "signout" then
        clearAccountView()
        m.connected = false
        m.savedScreens = {}
        m.stack = []
        m.items = []
        m.rows.content = invalid
        m.featureArt.uri = "pkg:/images/logo.png"
        showScreen("Settings", false)
        m.status.text = "Signed out. Your saved account and viewing history have been removed."
    else if r.op = "pairStart" then
        m.pairSession = r.session
        showPairDialog()
        m.pairTimer.control = "start"
        m.status.text = "Waiting for phone setup."
    else if r.op = "pairPoll" then
        if m.pairSession = invalid then return
        if m.connected then
            closeDialog()
            m.pairSession = invalid
            showScreen("Home", false)
        else
            m.status.text = "Waiting for phone setup."
            if m.top.dialog = invalid then showPairDialog()
            m.pairTimer.control = "start"
        end if
    else if r.op = "resolve" then
        startVideo(r.item)
    else if r.op = "guide" then
        lines = ""
        for each p in r.items
            line = p.title
            if p.startText <> invalid then line = p.startText + "  " + line
            lines += line + chr(10)
        end for
        if lines = "" then lines = r.message
        showDialog("Guide • " + m.selected.title, lines, ["Watch channel", "Retry guide", "Back"], "guide")
        m.status.text = r.message
    else if r.op = "favorites" then
        m.status.text = "Favorites updated."
        loadCatalog()
    else if r.op = "catalog" or r.op = "episodes" then
        m.items = r.items
        m.hasMore = r.hasMore
        m.complete = r.complete
        if r.categories <> invalid then m.categories = r.categories
        if r.seasons <> invalid then m.seasons = r.seasons
        m.status.text = r.total.toStr() + " results • Page " + (m.page + 1).toStr()
        scope = ""
        if type(r.scope) = "String" or type(r.scope) = "roString" then
            scope = r.scope.split(".")[0]
            if instr(1, scope, "TV provider pages loaded: ") = 1 then
                scope = scope.replace("TV provider pages loaded: ", "TV pages ").replace(" of up to ", "/")
            else if instr(1, scope, "Episodes from ") = 1 then
                scope = scope.replace("Episodes from ", "TV pages ").replace(" loaded provider TV pages", "")
            else
                scope = ""
            end if
        end if
        if scope <> "" then m.status.text += " • " + scope
        m.displayRows = []
        if m.screen = "Home" then
            if r.continue <> invalid then appendRow("Continue Watching", r.continue)
            if r.recent <> invalid then appendRow("Recently Watched", r.recent)
            appendRow("From your movie library", r.items)
        else
            appendRow(m.category, r.items)
        end if
        renderRows()
        if r.op = "episodes" and m.pickSeasonAfterLoad = true then
            m.pickSeasonAfterLoad = false
            showSeasons()
        end if
        if m.items.count() = 0 then
            m.featureTitle.text = "No items on this page"
            m.featureDescription.text = "Try another category or search. Provider downloads may be retried from Options."
            m.featureArt.uri = "pkg:/images/logo.png"
        end if
        telemetry({event: "catalog", screen: m.screen, count: r.items.count(), has_more: r.hasMore})
    end if
end sub

sub appendRow(title as string, items as object)
    if items.count() = 0 then return
    bounded = []
    for each item in items
        if bounded.count() < 30 then bounded.push(item)
    end for
    m.displayRows.push({title: title, items: bounded})
end sub

sub renderRows()
    root = CreateObject("roSGNode", "ContentNode")
    for each row in m.displayRows
        rowNode = root.createChild("ContentNode")
        rowNode.title = row.title
        for each item in row.items
            node = rowNode.createChild("ContentNode")
            node.title = item.title
            node.hdPosterUrl = item.artwork
        end for
    end for
    m.rows.content = root
    m.rows.visible = true
    if m.displayRows.count() > 0 then
        m.selected = m.displayRows[0].items[0]
        updateFeature(m.selected)
        if m.restoreFocus <> invalid then
            m.rows.jumpToRowItem = m.restoreFocus
            m.restoreFocus = invalid
        end if
    end if
    if m.focusAfterLoad then
        m.focusAfterLoad = false
        focusContent()
    end if
end sub

sub updateFeature(item as object)
    m.featureTitle.text = item.title
    m.featureEyebrow.text = "APEX AFTER DARK  /  " + ucase(item.kind)
    if item.favorite = true then m.featureEyebrow.text += "  /  FAVORITE"
    m.featureDescription.text = item.description
    if m.featureDescription.text = "" then m.featureDescription.text = item.category
    art = item.artwork
    if item.backdrop <> invalid then
        if item.backdrop <> "" then art = item.backdrop
    end if
    if art = "" then art = "pkg:/images/logo.png"
    m.featureArt.uri = art
    if item.kind = "series" then
        m.featureHint.text = "OK  Browse seasons and episodes"
    else if m.screen = "Guide" then
        m.featureHint.text = "OK  View channel guide"
    else
        m.featureHint.text = "OK  Details    Play button  Watch now"
    end if
end sub

sub onNavSelected()
    index = m.nav.itemSelected
    if index >= 0 and index < m.navNames.count() then showScreen(m.navNames[index], true)
end sub

sub rememberScreen()
    if m.screen = "Settings" then return
    state = {screen: m.screen, kind: m.kind, category: m.category, query: m.query, page: m.page, focus: m.rows.rowItemFocused}
    if m.stack.count() > 0 then
        parent = m.stack[0]
        state.category = parent.category
        state.query = parent.query
        state.page = parent.page
        state.focus = parent.focus
    end if
    m.savedScreens[m.screen] = state
end sub

sub showScreen(name as string, preserve as boolean)
    invalidateRequest()
    m.notice.visible = false
    if preserve then rememberScreen()
    if name <> m.screen or (m.seriesId <> invalid and m.seriesId <> "") or m.stack.count() > 0 then
        m.items = []
        m.displayRows = []
        m.rows.content = invalid
        m.selected = invalid
        m.hasMore = false
        m.categories = ["All"]
        m.seasons = []
        m.featureArt.uri = "pkg:/images/logo.png"
        m.restoreFocus = invalid
    end if
    m.stack = []
    m.seriesId = ""
    m.season = invalid
    m.screen = name
    m.heading.text = name
    m.feature.visible = name <> "Settings"
    m.actions.visible = name = "Settings"
    m.rows.visible = name <> "Settings"
    m.category = "All"
    m.query = ""
    m.page = 0
    if m.savedScreens.doesExist(name) then
        saved = m.savedScreens[name]
        m.category = saved.category
        m.query = saved.query
        m.page = saved.page
        m.restoreFocus = saved.focus
    end if
    if name = "Settings" then
        showSettings()
        return
    end if
    if not m.connected then
        m.rows.content = invalid
        m.status.text = "Not connected. Open Settings to connect your Apollo account."
        return
    end if
    m.kind = "movie"
    if name = "TV Shows" then m.kind = "series"
    if name = "Live TV" or name = "Guide" then m.kind = "live"
    if name = "Favorites" then m.kind = "favorites"
    if name = "Search" then m.kind = "all"
    m.focusAfterLoad = true
    loadCatalog()
    if name = "Search" and m.query = "" then showKeyboard("Search movies, shows and channels", "search", "", false)
    telemetry({event: "screen", screen: name})
end sub

sub showSettings()
    status = "Not connected"
    if m.connected then status = "Apollo connected • Saved sign-in enabled"
    m.status.text = status + " • " + m.deviceSummary
    m.actionNames = ["Connect Apollo username & password", "Connect using your phone", "Reconnect saved account", "Sign out", "Multi-View capabilities", "Test error recovery", "About Apex After Dark"]
    m.actions.content = makeList(m.actionNames)
    m.actions.setFocus(true)
    m.footer.text = "Left Navigation    OK Select    Back Home"
end sub

sub loadCatalog(loadMore = false as boolean, refresh = false as boolean)
    if m.connected and m.displayRows.count() = 0 then
        m.featureTitle.text = "Loading your library"
        m.featureDescription.text = "Your account is saved. Getting your movies, shows and channels ready."
        m.featureHint.text = "You can browse when the library is ready"
    end if
    if m.seriesId <> invalid and m.seriesId <> "" then
        req = {op: "episodes", seriesId: m.seriesId, query: m.query, page: m.page, loadMore: loadMore, refresh: refresh}
        if m.season <> invalid then req.season = m.season
    else
        req = {op: "catalog", kind: m.kind, category: m.category, query: m.query, page: m.page, loadMore: loadMore, refresh: refresh}
    end if
    sendRequest(req)
    m.footer.text = "OK Details    * Options / categories    Replay Previous page    FF Next page"
end sub

sub focusContent()
    if m.screen = "Settings" then
        m.actions.setFocus(true)
    else if m.displayRows.count() > 0 then
        m.rows.setFocus(true)
    else
        m.nav.setFocus(true)
    end if
end sub

function focusedItem() as dynamic
    if m.loading then return invalid
    rowPosition = m.rows.rowItemFocused
    if rowPosition = invalid then return invalid
    if rowPosition.count() < 2 then return invalid
    if rowPosition[0] < 0 or rowPosition[0] >= m.displayRows.count() then return invalid
    row = m.displayRows[rowPosition[0]].items
    if rowPosition[1] < 0 or rowPosition[1] >= row.count() then return invalid
    return row[rowPosition[1]]
end function

sub onItemFocused()
    item = focusedItem()
    if item = invalid then return
    m.selected = item
    updateFeature(item)
end sub

sub onItemSelected()
    item = focusedItem()
    if item = invalid then return
    m.selected = item
    if item.kind = "series" then
        m.stack.push({title: m.heading.text, seriesId: m.seriesId, season: m.season, page: m.page, category: m.category, query: m.query, focus: m.rows.rowItemFocused})
        m.seriesId = item.id
        m.season = invalid
        m.query = ""
        m.pickSeasonAfterLoad = true
        m.page = 0
        m.restoreFocus = [0,0]
        m.heading.text = item.title
        m.focusAfterLoad = true
        loadCatalog()
    else if m.screen = "Guide" then
        sendRequest({op: "guide", channel: item})
    else
        buttons = ["Play", "Back"]
        if item.kind = "live" then buttons = ["Watch live", "Toggle favorite", "Channel guide", "Back"]
        description = detailMessage(item)
        if item.resumePosition <> invalid then
            if item.resumePosition > 15 then buttons[0] = "Resume playback"
        end if
        showDialog(item.title, description, buttons, "details")
    end if
end sub

function detailMessage(item as object) as string
    description = item.description
    if type(description) <> "String" and type(description) <> "roString" then description = ""
    description = description.trim()
    if description = "" then return "Details are not provided for this title."
    return description
end function

sub onActionSelected()
    index = m.actions.itemSelected
    if index = 0 then
        showKeyboard("Apollo username", "username", "", false)
    else if index = 1 then
        sendRequest({op: "pairStart", relayUrl: m.relay})
    else if index = 2 then
        sendRequest({op: "restore", relayUrl: m.relay})
    else if index = 3 then
        showDialog("Sign out?", "Remove the saved Apollo account, favorites and viewing history from this Roku?", ["Keep signed in", "Sign out"], "signout")
    else if index = 4 then
        showDialog("Multi-View on this Roku", "Independent simultaneous video is not enabled on this device. Roku documents one video prebuffer at a time. A single server-composited stream is a possible alternative, but no infrastructure has been provisioned." + chr(10) + "Reported hardware: " + m.deviceSummary, ["Back"], "info")
    else if index = 5 then
        showDialog("Request unavailable", "This is a local recovery test. No provider request was made. Back and the buttons below remain usable.", ["Return Home", "Back"], "recoveryTest")
    else if index = 6 then
        showDialog("Apex After Dark", "Native Roku build 1.0.00006" + chr(10) + "BrightScript + SceneGraph. Real Apollo catalogs. Stored sign-in is encrypted by Roku and scoped to the developer ID. Removing the app or changing its signing identity may remove saved data.", ["Back"], "info")
    end if
end sub

sub showKeyboard(title as string, kind as string, value as string, secure as boolean)
    closeDialog()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = title
    dialog.text = value
    dialog.buttons = ["Continue", "Cancel"]
    dialog.backgroundUri = "pkg:/images/backdrop.png"
    dialog.keyboard.textEditBox.secureMode = secure
    dialog.observeField("buttonSelected", "onDialogButton")
    dialog.observeField("wasClosed", "onDialogClosed")
    m.dialogKind = kind
    m.top.dialog = dialog
end sub

sub showDialog(title as string, message as string, buttons as object, kind as string)
    closeDialog()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    dialog.message = message
    dialog.buttons = buttons
    dialog.backgroundUri = "pkg:/images/backdrop.png"
    dialog.observeField("buttonSelected", "onDialogButton")
    dialog.observeField("wasClosed", "onDialogClosed")
    m.dialogKind = kind
    m.top.dialog = dialog
end sub

sub closeDialog()
    dialog = m.top.dialog
    if dialog <> invalid then
        dialog.unobserveField("buttonSelected")
        dialog.unobserveField("wasClosed")
        dialog.close = true
        m.top.dialog = invalid
    end if
    m.dialogKind = ""
end sub

sub onDialogClosed()
    kind = m.dialogKind
    m.dialogKind = ""
    if kind = "pair" then
        cancelPair()
    end if
    if kind = "password" or kind = "username" then m.pendingUsername = invalid
    focusContent()
end sub

sub onDialogButton()
    dialog = m.top.dialog
    if dialog = invalid then return
    index = dialog.buttonSelected
    kind = m.dialogKind
    text = ""
    if kind = "username" or kind = "password" or kind = "search" then text = dialog.text
    closeDialog()
    if kind = "username" and index = 0 then
        if text.trim() = "" then
            showKeyboard("Enter your Apollo username", "username", "", false)
            return
        end if
        m.pendingUsername = text.trim()
        showKeyboard("Apollo password", "password", "", true)
    else if kind = "password" and index = 0 then
        if text = "" then
            showKeyboard("Enter your Apollo password", "password", "", true)
            return
        end if
        sendRequest({op: "login", username: m.pendingUsername, password: text})
        m.pendingUsername = invalid
        text = ""
    else if kind = "search" and index = 0 then
        m.query = text.trim()
        m.page = 0
        m.focusAfterLoad = true
        loadCatalog()
    else if kind = "exit" and index = 1 then
        m.api.control = "STOP"
        m.top.exitRequested = true
    else if kind = "signout" and index = 1 then
        m.savedScreens = {}
        m.stack = []
        sendRequest({op: "signout"})
    else if kind = "details" then
        if index = 0 then
            playSelected()
        else if m.selected.kind = "live" and index = 1 then
            sendRequest({op: "favorites", item: m.selected})
        else if m.selected.kind = "live" and index = 2 then
            sendRequest({op: "guide", channel: m.selected})
        else
            focusContent()
        end if
    else if kind = "guide" then
        if index = 0 then
            playSelected()
        else if index = 1 then
            sendRequest({op: "guide", channel: m.selected})
        else
            focusContent()
        end if
    else if kind = "requestError" then
        if index = 0 then
            if m.lastRequest.op = "login" then
                showKeyboard("Apollo username", "username", "", false)
            else if m.lastRequest.op = "pairPoll" then
                pollPair()
            else
                sendRequest(m.lastRequest)
            end if
        else if index = 1 then
            showScreen("Settings", true)
        else
            focusContent()
        end if
    else if kind = "playerError" then
        if index = 0 then
            playSelected()
        else if index = 1 then
            showScreen("Settings", true)
        else
            focusContent()
        end if
    else if kind = "pair" then
        if index = 0 then
            pollPair()
        else
            cancelPair()
            focusContent()
        end if
    else if kind = "options" then
        handleOption(index)
    else if kind = "picker" then
        handleChoice(index)
    else if kind = "recoveryTest" and index = 0 then
        showScreen("Home", true)
    else
        m.pendingUsername = invalid
        focusContent()
    end if
end sub

function refreshOptionLabel() as string
    if m.seriesId <> invalid and m.seriesId <> "" then return "Refresh this show's first TV page"
    if m.kind = "series" then return "Refresh first TV page"
    if m.kind = "all" then return "Refresh movies/live and first TV page"
    return "Refresh"
end function

sub showOptions()
    m.optionNames = ["Categories", "Search this library", "Next page", "Previous page", "Load more provider catalog", refreshOptionLabel(), "Back"]
    if m.seriesId <> invalid and m.seriesId <> "" then m.optionNames[0] = "Seasons"
    showDialog("Browse options", "Search covers the loaded catalog. Load more provider pages to expand TV results.", m.optionNames, "options")
end sub

sub handleOption(index as integer)
    if index = 0 then
        if m.seriesId <> invalid and m.seriesId <> "" then
            showSeasons()
        else
            m.categoryChoices = m.categories
            if m.categoryChoices.count() = 0 then m.categoryChoices = ["All"]
            showChoices("category", m.categoryChoices, 0)
        end if
    else if index = 1 then
        showKeyboard("Search this library", "search", m.query, false)
    else if index = 2 then
        nextPage()
    else if index = 3 then
        previousPage()
    else if index = 4 then
        m.focusAfterLoad = true
        loadCatalog(true)
    else if index = 5 then
        m.page = 0
        m.focusAfterLoad = true
        loadCatalog(false, true)
    else
        focusContent()
    end if
end sub

sub showChoices(kind as string, choices as object, page as integer)
    m.choiceKind = kind
    m.choices = choices
    m.choicePage = page
    selection = ChoicePage(choices, page)
    m.choiceOffset = selection.offset
    m.choiceCount = selection.items.count()
    buttons = selection.items
    m.choicePrevious = -1
    m.choiceNext = -1
    if selection.hasPrevious then
        m.choicePrevious = buttons.count()
        buttons.push("Previous choices")
    end if
    if selection.hasNext then
        m.choiceNext = buttons.count()
        buttons.push("More choices")
    end if
    buttons.push("Back")
    showDialog("Choose " + kind, "Page " + (page + 1).toStr() + " • From your provider library", buttons, "picker")
end sub

sub handleChoice(index as integer)
    if index = m.choicePrevious then
        showChoices(m.choiceKind, m.choices, m.choicePage - 1)
    else if index = m.choiceNext then
        showChoices(m.choiceKind, m.choices, m.choicePage + 1)
    else if index < m.choiceCount then
        if m.choiceKind = "season" then
            m.season = m.seasons[m.choiceOffset + index]
            m.restoreFocus = [0,0]
        else
            m.category = m.choices[m.choiceOffset + index]
        end if
        m.page = 0
        m.focusAfterLoad = true
        loadCatalog()
    else
        focusContent()
    end if
end sub

sub nextPage()
    if m.hasMore then
        m.page++
        m.focusAfterLoad = true
        loadCatalog()
    else
        m.status.text = "End of loaded results. Options can load more provider TV pages."
        focusContent()
    end if
end sub

sub previousPage()
    if m.page > 0 then
        m.page--
        m.focusAfterLoad = true
        loadCatalog()
    else
        focusContent()
    end if
end sub

sub pollPair()
    if m.pairSession = invalid then return
    sendRequest({op: "pairPoll", session: m.pairSession})
end sub

sub showPairDialog()
    if m.pairSession = invalid then return
    showDialog("Connect with your phone", "Open this private setup link on your phone. Use your Apollo username, not an email address." + chr(10) + m.pairSession.setupUrl, ["Check connection", "Cancel"], "pair")
end sub

sub cancelPair()
    invalidateRequest()
    m.pairTimer.control = "stop"
    if m.pairSession <> invalid then sendRequest({op: "pairCancel", session: m.pairSession}, false)
    m.pairSession = invalid
end sub

sub showSeasons()
    names = []
    for each season in m.seasons
        label = "Season " + season.toStr()
        if season = 0 then label = "Season 0 / unnumbered"
        names.push(label)
    end for
    if names.count() = 0 then
        showDialog("Seasons unavailable", "The provider has not supplied season numbers for these entries.", ["Back"], "info")
    else
        showChoices("season", names, 0)
    end if
end sub

sub onPairTimer()
    pollPair()
end sub

sub playSelected()
    if m.selected = invalid then return
    if m.selected.kind = "series" then
        onItemSelected()
        return
    end if
    m.returnFocus = m.rows.rowItemFocused
    sendRequest({op: "resolve", item: m.selected})
end sub

sub startVideo(item as object)
    if m.playing then stopVideo()
    m.selected = item
    m.playItem = item
    m.playbackStarted = false
    m.lastPlaybackPosition = invalid
    m.lastPlaybackDuration = 0
    content = CreateObject("roSGNode", "ContentNode")
    content.title = item.title
    content.url = item.url
    content.streamFormat = item.format
    if item.headers <> invalid then
        headers = []
        for each name in item.headers
            headers.push(name + ": " + item.headers[name])
        end for
        content.httpHeaders = headers
    end if
    content.live = item.kind = "live"
    if item.resumePosition <> invalid and item.kind <> "live" then content.playStart = item.resumePosition
    m.video.content = content
    m.video.visible = true
    m.shell.visible = false
    m.playing = true
    m.video.enableUI = true
    m.video.setFocus(true)
    m.video.control = "play"
    m.startupTimer.control = "start"
    m.saveTimer.control = "start"
    telemetry({event: "play_requested", kind: item.kind})
end sub

sub onVideoState()
    state = m.video.state
    diagnostics = {event: "player_state", state: state, error_code: m.video.errorCode}
    info = m.video.errorInfo
    if state = "error" and type(info) = "roAssociativeArray" then
        if type(info.category) = "String" or type(info.category) = "roString" then
            for each category in ["http", "drm", "mediaerror", "mediaplayer"]
                if info.category = category then diagnostics.error_category = category
            end for
        end if
        if type(info.errcode) = "Integer" or type(info.errcode) = "roInt" then diagnostics.error_detail_code = info.errcode
        if type(info.drmerrcode) = "Integer" or type(info.drmerrcode) = "roInt" then diagnostics.drm_error_code = info.drmerrcode
    end if
    telemetry(diagnostics)
    if not m.playing then return
    if state = "playing" then
        m.playbackStarted = true
        m.startupTimer.control = "stop"
    else if state = "buffering" then
        m.startupTimer.control = "start"
    else if state = "error" then
        code = m.video.errorCode
        stopVideo()
        showDialog("Playback unavailable", "This stream could not play (code " + code.toStr() + "). It may be unavailable or use a format this TV cannot decode. Try again or select another title.", ["Try again", "Connection settings", "Back to library"], "playerError")
    else if state = "finished" then
        if m.video.duration > 0 then
            m.lastPlaybackPosition = m.video.duration
            m.lastPlaybackDuration = m.video.duration
        end if
        savePlayback()
        stopVideo()
    end if
end sub

sub onVideoPosition()
    if not m.playing then return
    if m.playbackStarted then
        state = m.video.state
        if state = "playing" or state = "paused" or state = "buffering" then
            if m.video.position >= 0 then m.lastPlaybackPosition = m.video.position
            if m.video.duration > 0 then m.lastPlaybackDuration = m.video.duration
        end if
    end if
    telemetry({event: "playback_position", kind: m.playItem.kind, position: m.video.position, duration: m.video.duration})
end sub

sub onDownloadedSegment()
    segment = m.video.downloadedSegment
    if type(segment) <> "roAssociativeArray" then return
    data = {event:"segment_download"}
    mapping = {Status:"status", SegSequence:"sequence", SegStart:"position", SegType:"segment_type", BitrateBPS:"bitrate", Width:"width", Height:"height", SegSize:"bytes", DownloadDuration:"elapsed_ms"}
    for each field in mapping
        value = segment[field]
        kind = type(value)
        if kind = "Integer" or kind = "roInt" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble" or kind = "LongInteger" then
            data[mapping[field]] = value
        end if
    end for
    telemetry(data)
end sub

sub savePlayback()
    if not m.playing then return
    if not m.playbackStarted then return
    if m.lastPlaybackPosition = invalid then return
    sendRequest({op: "saveProgress", item: m.playItem, position: m.lastPlaybackPosition, duration: m.lastPlaybackDuration}, false)
end sub

sub stopVideo()
    if m.playing then savePlayback()
    m.playing = false
    m.startupTimer.control = "stop"
    m.saveTimer.control = "stop"
    m.video.control = "stop"
    m.video.visible = false
    m.video.content = invalid
    m.shell.visible = true
    if m.returnFocus <> invalid then m.rows.jumpToRowItem = m.returnFocus
    focusContent()
    telemetry({event: "player_closed", screen: m.screen})
end sub

sub onStartupTimeout()
    if not m.playing then return
    stopVideo()
    showDialog("Stream timed out", "The stream did not start or stopped responding. Try again or choose another title.", ["Try again", "Connection settings", "Back to library"], "playerError")
end sub

sub returnBack()
    action = NavBack(m.top.dialog <> invalid, m.playing, m.stack.count(), m.screen)
    keepCatalog = false
    if action = "dialog" and m.lastRequest <> invalid and m.dialogKind <> "pair" then
        keepCatalog = m.lastRequest.op = "catalog" or m.lastRequest.op = "episodes"
    end if
    if not keepCatalog then invalidateRequest()
    if action = "dialog" then
        if m.dialogKind = "pair" then
            cancelPair()
        end if
        m.pendingUsername = invalid
        closeDialog()
        focusContent()
    else if action = "player" then
        stopVideo()
    else if action = "stack" then
        state = m.stack.pop()
        m.heading.text = state.title
        m.seriesId = state.seriesId
        m.season = state.season
        m.page = state.page
        m.category = state.category
        m.query = state.query
        m.restoreFocus = state.focus
        m.focusAfterLoad = true
        loadCatalog()
    else if action = "home" then
        showScreen("Home", true)
    else
        showDialog("Leave Apex After Dark?", "Your sign-in and viewing progress stay saved.", ["Stay here", "Exit to Roku Home"], "exit")
    end if
end sub

sub invalidateRequest()
    m.activeId = -1
    m.loading = false
end sub

sub clearAccountView()
    m.selected = invalid
    m.playItem = invalid
    m.displayRows = []
    m.items = []
    m.lastRequest = invalid
    m.pendingUsername = invalid
    m.pairSession = invalid
    m.savedScreens = {}
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" then
        returnBack()
        return true
    end if
    if m.playing then
        if m.playItem.kind = "live" and (key = "up" or key = "down") then
            direction = 1
            if key = "up" then direction = -1
            switchChannel(direction)
            return true
        end if
        return false
    end if
    if m.top.dialog <> invalid then return false
    if m.screen = "Settings" and (key = "play" or key = "fastforward" or key = "rewind" or key = "replay") then return false
    if key = "left" then
        m.nav.setFocus(true)
        return true
    else if key = "right" and m.nav.hasFocus() then
        focusContent()
        return true
    else if key = "options" then
        if m.screen <> "Settings" then showOptions()
        return true
    else if key = "fastforward" then
        nextPage()
        return true
    else if key = "replay" or key = "rewind" then
        previousPage()
        return true
    else if key = "play" then
        m.selected = focusedItem()
        playSelected()
        return true
    end if
    return false
end function

sub switchChannel(direction as integer)
    live = []
    for each item in m.items
        if item.kind = "live" then live.push(item)
    end for
    if live.count() < 2 then return
    for index = 0 to live.count() - 1
        if live[index].id = m.playItem.id then
            nextIndex = (index + direction + live.count()) mod live.count()
            stopVideo()
            m.selected = live[nextIndex]
            playSelected()
            return
        end if
    end for
end sub
