sub init()
    m.top.functionName = "RunWorker"
end sub

sub RunWorker()
    m.port = createObject("roMessagePort")
    m.top.observeField("request", m.port)
    m.registry = createObject("roRegistrySection", "ApexNativePrivate")
    m.lastRequestId = invalid
    ApiResetMemory()
    pending = m.top.request
    if CoreAA(pending)
        m.top.request = invalid
        m.lastRequestId = pending.id
        m.top.response = ApiDispatch(pending)
    end if
    while true
        event = wait(0, m.port)
        if type(event) = "roSGNodeEvent"
            request = event.getData()
            if CoreAA(request)
                current = m.top.request
                if CoreAA(current)
                    if current.id = request.id then m.top.request = invalid
                end if
                if request.id <> m.lastRequestId
                    m.lastRequestId = request.id
                    m.top.response = ApiDispatch(request)
                end if
            end if
        end if
    end while
end sub

sub ApiResetMemory()
    m.credentials = invalid
    m.auth = invalid
    m.connected = false
    m.live = []
    m.movies = invalid
    m.seriesRows = []
    m.series = []
    m.seriesPage = 0
    m.loadedSeriesPages = {}
    m.seriesEndPage = 20
    m.seriesComplete = false
    m.seriesError = ""
    m.lookup = {}
    m.progress = {}
    m.favorites = {}
    m.metadata = {}
    m.metadataAttempts = {}
    m.metadataBrowse = {}
    m.pairSession = invalid
    m.cancelledPairSession = invalid
    m.epg = invalid
    m.persistenceFailed = false
end sub

function ApiNow() as double
    return createObject("roDateTime").asSeconds() * 1.0#
end function

function ApiDispatch(request as object) as object
    op = CoreString(request.op)
    result = {id:request.id, op:op, ok:true, items:[], total:0, hasMore:false, message:""}
    if op = "restore"
        ApiResetMemory()
        saved = parseJson(m.registry.read("credentials"))
        history = parseJson(m.registry.read("progress"))
        favorites = parseJson(m.registry.read("favorites"))
        if CoreAA(history) then m.progress = history
        if CoreAA(favorites) then m.favorites = favorites
        if CoreAA(saved)
            kind = CoreString(saved.kind, "apollo")
            valid = false
            if kind = "apollo"
                valid = CoreString(saved.username).trim() <> "" and CoreString(saved.password) <> ""
            else if kind = "m3u"
                valid = CoreString(saved.playlistUrl).trim() <> ""
            end if
            if valid
                ' Saved sign-in survives an unavailable provider. Catalog requests
                ' retry independently; only explicit signout removes the account.
                m.credentials = saved
                m.connected = true
            end if
        end if
        if not m.connected
            result.message = "Connect your Apollo account to browse."
        end if
    else if op = "login"
        credentials = {kind:"apollo", username:CoreString(request.username).trim(), password:CoreString(request.password), baseUrl:CoreString(request.baseUrl, "https://tvnow.best"), epgUrl:CoreString(request.epgUrl)}
        if credentials.username = "" or credentials.password = ""
            result.ok = false
            result.message = "Enter your Apollo username and password."
        else
            result.ok = ApiConnect(credentials, true)
            if not result.ok then result.message = "Apollo could not connect. Check account details and network connection."
            if m.persistenceFailed then result.message = "Account verified, but Roku could not save sign-in. Free some app storage and try again."
        end if
    else if op = "pairStart"
        relay = CoreString(request.relayUrl)
        if relay = "" then relay = CoreString(request.baseUrl)
        relay = ApiTrimSlash(relay)
        if left(relay, 8) <> "https://"
            result.ok = false
            result.message = "Phone setup needs a configured HTTPS relay. Use account sign in."
        else
            headers = {"Content-Type":"application/json"}
            token = CoreString(request.provisioningToken)
            if token <> "" then headers["x-device-provisioning-token"] = token
            response = ApiHttp(relay + "/api/pair/start", "POST", headers, "", 15000)
            session = ApiJson(response)
            if response.ok and CoreValidSession(session)
                session.baseUrl = relay
                m.pairSession = session
                result.session = session
                result.message = "Open the setup link on your phone."
            else
                result.ok = false
                result.message = "Phone setup could not start. Try again or use account sign in."
            end if
        end if
    else if op = "pairPoll"
        result = ApiPollPair(request, result)
    else if op = "pairCancel"
        cancelled = m.pairSession
        if not CoreValidSession(cancelled) then cancelled = m.cancelledPairSession
        m.pairSession = invalid
        m.cancelledPairSession = invalid
        if CoreValidSession(cancelled)
            ApiHttp(cancelled.baseUrl + "/api/pair/" + cancelled.code + "/cancel", "DELETE", {Authorization:"Bearer " + cancelled.pollToken}, "", 4000)
        end if
        result.message = "Phone setup closed."
    else if op = "signout"
        if CoreValidSession(m.pairSession)
            ApiHttp(m.pairSession.baseUrl + "/api/pair/" + m.pairSession.code + "/cancel", "DELETE", {Authorization:"Bearer " + m.pairSession.pollToken}, "", 4000)
        end if
        removed = ApiErasePrivate()
        ApiResetMemory()
        result.message = "Signed out. Account and viewing history removed."
        if not removed
            result.ok = false
            result.message = "Signed out for this session, but Roku could not clear saved data. Remove this app to erase its stored account."
        end if
    else if op = "catalog"
        result = ApiCatalog(request, result)
    else if op = "episodes"
        result = ApiEpisodes(request, result)
    else if op = "resolve"
        result = ApiResolve(request, result)
    else if op = "guide"
        result = ApiGuide(request, result)
    else if op = "saveProgress"
        if CoreAA(request.item)
            itemId = CoreString(request.item.id)
            if itemId <> "" and m.connected
                record = CoreProgress(request.item, CoreNumber(request.position), CoreNumber(request.duration), ApiNow())
                m.progress[itemId] = record
                ApiTrimProgress()
                result.ok = ApiSave("progress", m.progress)
                if not result.ok then result.message = "Roku could not save the resume position."
            end if
        end if
    else if op = "favorites"
        if CoreAA(request.item)
            itemId = CoreString(request.item.id)
            if itemId <> "" and m.connected
                if m.favorites.doesExist(itemId)
                    m.favorites.delete(itemId)
                else
                    if m.favorites.count() >= 100
                        result.ok = false
                        result.message = "You have 100 favorites. Remove one before adding another."
                    else
                        m.favorites[itemId] = true
                    end if
                end if
                if result.ok
                    result.ok = ApiSave("favorites", m.favorites)
                    if not result.ok then result.message = "Roku could not save the favorite change."
                end if
                result.favorite = m.favorites.doesExist(itemId)
                result.itemId = itemId
            end if
        end if
    else
        result.ok = false
        result.message = "This action is not available."
    end if
    result.connected = m.connected
    result.recent = ApiHistory(false)
    result.continue = ApiHistory(true)
    result.capabilities = {multiView:false, concurrentPlayers:1, provider:"Apollo", searchScope:"Loaded provider inventory"}
    return result
end function

function ApiSave(key as string, data as object) as boolean
    written = m.registry.write(key, formatJson(data))
    flushed = m.registry.flush()
    return written and flushed
end function

function ApiErasePrivate() as boolean
    removed = true
    for each key in ["credentials", "progress", "favorites"]
        if m.registry.exists(key)
            if not m.registry.delete(key) then removed = false
        end if
    end for
    flushed = m.registry.flush()
    return removed and flushed
end function

function ApiTrimSlash(value as string) as string
    while right(value, 1) = "/"
        value = left(value, len(value) - 1)
    end while
    return value
end function

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    response = {ok:false, code:0, body:"", headers:{}}
    if left(lcase(url), 8) <> "https://" and left(lcase(url), 7) <> "http://" then return response
    transfer = createObject("roUrlTransfer")
    port = createObject("roMessagePort")
    transfer.setMessagePort(port)
    transfer.setCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.initClientCertificates()
    transfer.enablePeerVerification(true)
    transfer.enableHostVerification(true)
    transfer.enableEncodings(true)
    transfer.setUrl(url)
    transfer.retainBodyOnError(true)
    for each name in headers
        value = CoreString(headers[name])
        if createObject("roRegex", "^[A-Za-z0-9_-]+$", "").isMatch(name)
            if instr(1, value, chr(10)) = 0 and instr(1, value, chr(13)) = 0 then transfer.addHeader(name, value)
        end if
    end for
    transfer.setRequest(method)
    if method = "POST"
        started = transfer.asyncPostFromString(body)
    else if method = "HEAD"
        started = transfer.asyncHead()
    else
        started = transfer.asyncGetToString()
    end if
    if not started then return response
    timer = createObject("roTimespan")
    timer.mark()
    while timer.totalMilliseconds() < timeout
        remaining = timeout - timer.totalMilliseconds()
        if remaining < 1 then remaining = 1
        event = wait(remaining, port)
        if type(event) = "roUrlEvent"
            if event.getSourceIdentity() = transfer.getIdentity()
                response.code = event.getResponseCode()
                response.ok = response.code >= 200 and response.code < 300
                response.body = event.getString()
                response.headers = event.getResponseHeaders()
                return response
            end if
        end if
    end while
    transfer.asyncCancel()
    return response
end function

function ApiJson(response as object) as object
    if not response.ok then return {}
    value = parseJson(response.body)
    if CoreAA(value) then return value
    return {}
end function

function ApiConnect(credentials as object, persist as boolean, pairing = false as boolean) as boolean
    m.persistenceFailed = false
    if CoreString(credentials.kind, "apollo") = "apollo"
        if CoreString(credentials.username) = "" or CoreString(credentials.password) = "" then return false
    else if CoreString(credentials.playlistUrl) = ""
        return false
    end if
    prior = m.credentials
    m.credentials = credentials
    url = ApiPlaylistUrl("livetv")
    response = ApiHttp(url, "GET", {}, "", 15000)
    if not response.ok
        m.credentials = prior
        return false
    end if
    rows = CoreParseM3U(response.body, "live")
    if rows.count() = 0
        m.credentials = prior
        return false
    end if
    if pairing
        if ApiPairCancelled()
            m.credentials = prior
            return false
        end if
    end if
    if persist
        saved = ApiErasePrivate()
        if saved then saved = ApiSave("credentials", credentials)
        if not saved
            m.persistenceFailed = true
            m.credentials = prior
            return false
        end if
        ApiResetMemory()
    end if
    m.credentials = credentials
    m.auth = invalid
    m.connected = true
    m.live = rows
    ApiIndex(rows)
    return true
end function

function ApiPlaylistUrl(path as string) as string
    if m.credentials = invalid then return ""
    if CoreString(m.credentials.kind) = "m3u" then return CoreString(m.credentials.playlistUrl)
    base = ApiTrimSlash(CoreString(m.credentials.baseUrl, "https://tvnow.best"))
    escape = createObject("roUrlTransfer")
    return base + "/api/list/" + escape.escape(CoreString(m.credentials.username)) + "/" + escape.escape(CoreString(m.credentials.password)) + "/m3u8/" + path
end function

function ApiPollPair(request as object, result as object) as object
    session = request.session
    if not CoreValidSession(session) then session = m.pairSession
    if not CoreValidSession(session)
        result.ok = false
        result.message = "Start a new phone setup session."
        return result
    end if
    base = CoreString(session.baseUrl)
    if left(base, 8) <> "https://" or CoreNumber(session.expiresAt) <= ApiNow() * 1000
        result.ok = false
        result.message = "Phone setup expired. Start a new session."
        return result
    end if
    headers = {Authorization:"Bearer " + session.pollToken}
    response = ApiHttp(base + "/api/pair/" + session.code + "/status", "GET", headers, "", 8000)
    status = ApiJson(response)
    if not response.ok
        result.ok = false
        result.message = "Could not check phone setup. Try again."
        return result
    end if
    result.session = session
    result.status = CoreString(status.status, "waiting")
    if result.status = "ready"
        if ApiPairCancelled()
            result.ok = false
            result.message = "Phone setup was cancelled."
            return result
        end if
        consumed = ApiHttp(base + "/api/pair/" + session.code + "/consume", "POST", headers, "", 8000)
        payload = ApiJson(consumed)
        if ApiPairCancelled()
            result.ok = false
            result.message = "Phone setup was cancelled."
            return result
        end if
        if CoreAA(payload.config)
            result.ok = ApiConnect(payload.config, true, true)
            m.pairSession = invalid
            result.delete("session")
            if result.ok
                result.message = "Account connected."
            else
                result.message = "Setup received, but Apollo did not connect. Start setup again or use account sign in."
                if m.persistenceFailed then result.message = "Account verified, but Roku could not save sign-in. Free app storage and start setup again."
            end if
        else
            result.ok = false
            result.message = "Could not receive account setup. Start a new session."
        end if
    else
        result.message = "Waiting for phone setup."
    end if
    return result
end function

function ApiPairCancelled() as boolean
    if m.top = invalid then return false
    pending = m.top.request
    if CoreAA(pending)
        op = CoreString(pending.op)
        if op = "pairCancel" or op = "signout"
            m.cancelledPairSession = m.pairSession
            m.pairSession = invalid
            return true
        end if
    end if
    return false
end function

sub ApiIndex(rows as object)
    for each item in rows
        m.lookup[item.id] = item
        if CoreString(item.kind) = "series"
            for each episode in item.episodes
                m.lookup[episode.id] = episode
            end for
        end if
    end for
end sub

sub ApiUnindex(rows as object)
    for each item in rows
        m.lookup.delete(item.id)
        if CoreString(item.kind) = "series"
            for each episode in item.episodes
                m.lookup.delete(episode.id)
            end for
        end if
    end for
end sub

function ApiLoadLive(refresh = false as boolean) as boolean
    if not refresh and m.live.count() > 0 then return true
    if m.credentials = invalid then return false
    response = ApiHttp(ApiPlaylistUrl("livetv"), "GET", {}, "", 15000)
    if not response.ok then return false
    rows = CoreParseM3U(response.body, "live")
    if rows.count() = 0 then return false
    ApiUnindex(m.live)
    m.live = rows
    ApiIndex(rows)
    return true
end function

function ApiLoadMovies(refresh = false as boolean) as boolean
    if not refresh and m.movies <> invalid then return true
    if m.credentials = invalid then return false
    if CoreString(m.credentials.kind) = "m3u"
        m.movies = []
        return true
    end if
    response = ApiHttp(ApiPlaylistUrl("movies"), "GET", {}, "", 15000)
    if not response.ok then return false
    rows = CoreParseM3U(response.body, "movie")
    if rows.count() = 0 then return false
    if m.movies <> invalid then ApiUnindex(m.movies)
    m.movies = rows
    if CoreAA(m.metadataBrowse.movie) then m.metadataBrowse.movie.delete("preparedCount")
    ApiIndex(rows)
    return true
end function

function ApiLoadSeriesPage(requestedPage = 0 as integer, refresh = false as boolean) as boolean
    if not refresh and m.seriesComplete and requestedPage = 0 then return true
    if m.credentials = invalid then return false
    if CoreString(m.credentials.kind) = "m3u"
        m.seriesComplete = true
        return true
    end if
    page = requestedPage
    if page = 0 then page = m.seriesPage + 1
    if page < 1 or page > 20 then return false
    if not refresh and m.loadedSeriesPages.doesExist(page.toStr()) then return true
    response = ApiHttp(ApiPlaylistUrl("tvshows/" + page.toStr()), "GET", {}, "", 15000)
    if not response.ok
        m.seriesError = "Another TV catalog page could not load. Retry Load more."
        return false
    end if
    rows = CoreParseM3U(response.body, "episode")
    if rows.count() = 0
        if refresh
            m.seriesError = "TV catalog refresh returned no episodes. Try Refresh again."
            return false
        end if
        if page - 1 < m.seriesEndPage then m.seriesEndPage = page - 1
        m.seriesComplete = m.seriesPage >= m.seriesEndPage
        return true
    end if
    if refresh
        ' A successful refresh may expose pages added since the last empty page.
        m.seriesEndPage = 20
        m.seriesComplete = false
        freshIds = {}
        for each episode in rows
            freshIds[episode.id] = true
        end for
        retained = []
        for each episode in m.seriesRows
            if CoreNumber(episode.providerPage) <> page and not freshIds.doesExist(episode.id) then retained.push(episode)
        end for
        ApiUnindex(m.series)
        m.seriesRows = retained
    end if
    known = {}
    for each episode in m.seriesRows
        known[episode.id] = true
    end for
    for each episode in rows
        if not known.doesExist(episode.id)
            episode.providerPage = page
            m.seriesRows.push(episode)
            known[episode.id] = true
        end if
    end for
    m.loadedSeriesPages[page.toStr()] = true
    while m.seriesPage < m.seriesEndPage
        nextPage = m.seriesPage + 1
        if not m.loadedSeriesPages.doesExist(nextPage.toStr()) then exit while
        m.seriesPage = nextPage
    end while
    m.seriesComplete = m.seriesPage >= m.seriesEndPage
    m.series = CoreBuildSeries(m.seriesRows)
    if CoreAA(m.metadataBrowse.series) then m.metadataBrowse.series.delete("preparedCount")
    ApiIndex(m.series)
    m.seriesError = ""
    return true
end function

function ApiCatalog(request as object, result as object) as object
    if not m.connected
        result.ok = false
        result.message = "Connect your account first."
        return result
    end if
    kind = CoreString(request.kind, "movie")
    page = int(CoreNumber(request.page))
    rows = []
    complete = true
    loadOk = true
    refresh = request.refresh = true
    if kind = "movie"
        loadOk = ApiLoadMovies(refresh)
        if m.movies <> invalid then rows = m.movies
    else if kind = "series"
        if refresh
            loadOk = ApiLoadSeriesPage(1, true)
        else if m.seriesPage = 0 or request.loadMore = true
            loadOk = ApiLoadSeriesPage()
        end if
        rows = m.series
        complete = m.seriesComplete
    else if kind = "live"
        loadOk = ApiLoadLive(refresh)
        rows = m.live
    else if kind = "recent"
        rows = ApiHistory(false)
    else if kind = "continue"
        rows = ApiHistory(true)
    else if kind = "favorites"
        loadOk = ApiLoadLive(refresh)
        for each item in m.live
            if m.favorites.doesExist(item.id) then rows.push(item)
        end for
    else if kind = "all"
        loadOk = ApiLoadLive(refresh)
        if not ApiLoadMovies(refresh) then loadOk = false
        if refresh
            if not ApiLoadSeriesPage(1, true) then loadOk = false
        else if m.seriesPage = 0 or request.loadMore = true
            if not ApiLoadSeriesPage() then loadOk = false
        end if
        for each item in m.live
            rows.push(item)
        end for
        if m.movies <> invalid
            for each item in m.movies
                rows.push(item)
            end for
        end if
        for each item in m.series
            rows.push(item)
        end for
        complete = m.seriesComplete
    end if
    if not loadOk
        result.ok = false
        result.message = "Provider catalog could not load. Check connection and try again."
    end if
    if loadOk and page = 0 and (kind = "movie" or kind = "series")
        rows = ApiPrepareBrowse(rows, kind)
        if kind = "movie" then m.movies = rows else m.series = rows
    end if
    paged = CorePage(rows, CoreString(request.category, "All"), CoreString(request.query), page)
    if kind = "movie" or kind = "series" then ApiEnrich(paged.items, kind)
    if kind = "all"
        movieItems = []
        seriesItems = []
        for each item in paged.items
            if item.kind = "movie" then movieItems.push(item)
            if item.kind = "series" then seriesItems.push(item)
        end for
        ApiEnrich(movieItems, "movie")
        ApiEnrich(seriesItems, "series")
    end if
    for each item in paged.items
        ApiDecorate(item)
    end for
    result.append(paged)
    result.categories = CoreCategories(rows)
    result.complete = complete
    result.canLoadMore = not complete
    result.scope = "Loaded provider titles and categories; canonical metadata appears as you browse."
    if kind = "series" or kind = "all"
        result.scope = "TV provider pages loaded: " + m.loadedSeriesPages.count().toStr() + " of up to 20"
        if not complete then result.scope += ". More shows and episodes may be available."
        if refresh
            if loadOk then result.scope += ". Refreshed provider TV page 1; other loaded pages retained." else result.scope += ". Refresh requested provider TV page 1; cached titles remain available."
        end if
    end if
    return result
end function

function ApiEpisodes(request as object, result as object) as object
    if request.loadMore = true and request.refresh <> true then ApiLoadSeriesPage()
    show = m.lookup[CoreString(request.seriesId)]
    if not CoreAA(show)
        result.ok = false
        result.message = "This series is not in the loaded catalog."
        return result
    end if
    if CoreString(show.kind) <> "series" or type(show.episodes) <> "roArray"
        result.ok = false
        result.message = "Select a TV series to browse its episodes."
        return result
    end if
    refreshPage = 0
    if request.refresh = true
        refreshPage = 21
        for each episode in show.episodes
            providerPage = int(CoreNumber(episode.providerPage))
            if providerPage > 0 and providerPage < refreshPage then refreshPage = providerPage
        end for
        if refreshPage = 21 then refreshPage = 1
        if not ApiLoadSeriesPage(refreshPage, true)
            result.ok = false
            result.message = "Provider catalog could not refresh. Cached episodes remain available; try Refresh again."
        else
            show = m.lookup[CoreString(request.seriesId)]
            if not CoreAA(show)
                result.ok = false
                result.message = "This series is no longer in the refreshed provider catalog."
                return result
            end if
        end if
    end if
    rows = []
    seasons = []
    seen = {}
    for each item in show.episodes
        season = int(CoreNumber(item.season))
        key = season.toStr()
        if not seen.doesExist(key)
            seen[key] = true
            seasons.push(season)
        end if
        include = true
        if request.season <> invalid then include = season = CoreNumber(request.season)
        if include then rows.push(item)
    end for
    paged = CorePage(rows, "All", CoreString(request.query), int(CoreNumber(request.page)))
    for each item in paged.items
        if CoreString(item.artwork) = "" then item.artwork = CoreString(show.artwork)
        ApiDecorate(item)
    end for
    seasons.sort()
    result.append(paged)
    result.seasons = seasons
    result.series = CorePublicItem(show)
    result.complete = m.seriesComplete
    result.canLoadMore = not m.seriesComplete
    result.scope = "Episodes from " + m.loadedSeriesPages.count().toStr() + " loaded provider TV pages."
    if not m.seriesComplete then result.scope += " Load more to check for other seasons."
    if refreshPage > 0
        if result.ok then result.scope += " Refreshed provider TV page " + refreshPage.toStr() + "; other loaded pages retained." else result.scope += " Refresh requested provider TV page " + refreshPage.toStr() + "; cached episodes remain available."
    end if
    return result
end function

sub ApiDecorate(item as object)
    item.favorite = m.favorites.doesExist(item.id)
    record = m.progress[item.id]
    if CoreAA(record) then item.resumePosition = CoreNumber(record.position)
end sub

function ApiHistory(unfinished as boolean) as object
    records = []
    for each key in m.progress
        record = m.progress[key]
        if CoreAA(record) then records.push(record)
    end for
    records.sortBy("updatedAt", "r")
    items = []
    for each record in records
        include = true
        if unfinished then include = CoreNumber(record.position) >= 10
        item = m.lookup[CoreString(record.id)]
        if not CoreAA(item)
            if CoreAA(record.snapshot)
                item = {id:CoreString(record.id), kind:CoreString(record.kind)}
                item.append(record.snapshot)
            end if
        end if
        if CoreAA(item) and include
            copy = CorePublicItem(item)
            if CoreString(copy.id) = CoreString(record.id) and CoreString(copy.artwork) = "" and CoreAA(record.snapshot)
                copy.artwork = CoreSafeArtwork(record.snapshot.artwork)
            end if
            ApiDecorate(copy)
            items.push(copy)
            if items.count() >= 30 then exit for
        end if
    end for
    return items
end function

sub ApiTrimProgress()
    if m.progress.count() <= 12 then return
    records = []
    for each key in m.progress
        records.push(m.progress[key])
    end for
    records.sortBy("updatedAt", "r")
    retained = {}
    for i = 0 to 11
        record = records[i]
        retained[record.id] = record
    end for
    m.progress = retained
end sub

function ApiMetadataAuth() as boolean
    if m.auth <> invalid
        if CoreNumber(m.auth.expires) = 0 or CoreNumber(m.auth.expires) > ApiNow() then return true
    end if
    if m.credentials = invalid then return false
    if CoreString(m.credentials.username) = "" then return false
    headers = {Accept:"application/json", "Content-Type":"application/json", "User-Agent":"okhttp/4.9.3", "X-APP-VERSION":"2.6.1"}
    response = ApiHttp("https://dev.testbyte.top/api/login", "POST", headers, formatJson({username:m.credentials.username,password:m.credentials.password}), 8000)
    payload = ApiJson(response)
    if not CoreAA(payload.data) then return false
    token = CoreString(payload.data.token)
    tokenType = CoreString(payload.data.token_type, "Bearer")
    if token = "" then return false
    if instr(1, token, chr(10)) > 0 or instr(1, token, chr(13)) > 0 then return false
    if not createObject("roRegex", "^[A-Za-z]+$", "").isMatch(tokenType) then return false
    headers.Authorization = tokenType + " " + token
    response = ApiHttp("https://dev.testbyte.top/api/profiles", "GET", headers, "", 8000)
    profiles = ApiJson(response)
    if type(profiles.data) <> "roArray" then return false
    if profiles.data.count() = 0 then return false
    profile = profiles.data[0]
    if not CoreAA(profile) then return false
    profileId = CoreNumber(profile.profile_number, -1)
    if CoreAA(profile.settings) then profileId = CoreNumber(profile.settings.profile_id, profileId)
    if profileId < 0 or profileId > 2147483647 then return false
    if profileId <> int(profileId) then return false
    expiry = CoreNumber(payload.data.expires_at)
    if expiry > 1000000000000 then expiry /= 1000
    m.auth = {authorization:headers.Authorization, profile:profileId.toStr(), expires:expiry}
    return true
end function

function ApiMetadataArtwork(record as dynamic) as string
    if not CoreAA(record) then return ""
    if not CoreAA(record.meta) then return ""
    artwork = CoreSafeArtwork(record.meta.fanart)
    if artwork = "" then artwork = CoreSafeArtwork(record.meta.poster)
    if artwork = "" then artwork = CoreSafeArtwork(record.meta.banner)
    return artwork
end function

function ApiPrepareBrowse(rows as object, kind as string) as object
    if rows.count() = 0 then return rows
    state = m.metadataBrowse[kind]
    if not CoreAA(state)
        state = {attempts:0, complete:false, records:[]}
        m.metadataBrowse[kind] = state
    end if
    preserveOrder = CoreNumber(state.preparedCount, -1) = rows.count()
    if preserveOrder and (state.complete or state.attempts >= 2)
        ApiApplyMetadata(rows, kind)
        return rows
    end if
    targets = {}
    for each item in rows
        imdbId = CoreString(item.imdbId)
        if createObject("roRegex", "^tt\d+$", "").isMatch(imdbId)
            if not targets.doesExist(imdbId) then targets[imdbId] = []
            targets[imdbId].push(item)
        end if
    end for
    if targets.count() = 0 then return rows
    if not state.complete and state.attempts < 2
        state.attempts += 1
        if ApiMetadataAuth()
            headers = {Accept:"application/json", Authorization:m.auth.authorization, "X-API-PROFILE":m.auth.profile, "User-Agent":"okhttp/4.9.3", "X-APP-VERSION":"2.6.1"}
            path = "info/movie"
            if kind = "series" then path = "info/tvshow"
            response = ApiHttp("https://dev.testbyte.top/api/" + path + "/categories", "GET", headers, "", 3000)
            if response.code = 401 or response.code = 403 then m.auth = invalid
            payload = ApiJson(response)
            if type(payload.data) = "roArray"
                collections = []
                genres = []
                for each category in payload.data
                    if CoreAA(category)
                        categoryId = CoreNumber(category.id, -1)
                        if categoryId >= 0 and categoryId <= 2147483647 and categoryId = int(categoryId) and category.has_accessible_infos <> false
                            if category.is_genre = true then genres.push(categoryId) else collections.push(categoryId)
                        end if
                    end if
                end for
                selected = []
                if collections.count() > 0 then selected.push(collections.shift())
                if genres.count() > 0 then selected.push(genres.shift())
                if selected.count() < 2 and collections.count() > 0 then selected.push(collections.shift())
                if selected.count() < 2 and genres.count() > 0 then selected.push(genres.shift())
                state.complete = true
                illustrated = {}
                if kind = "series" then headers["X-API-Version"] = "V3"
                ' Keep initial browse enrichment bounded: at most two category pages.
                for each categoryId in selected
                    response = ApiHttp("https://dev.testbyte.top/api/" + path + "/items/" + categoryId.toStr() + "/0/250?use_lang_limits=0", "GET", headers, "", 3000)
                    if response.code = 401 or response.code = 403 then m.auth = invalid
                    payload = ApiJson(response)
                    records = invalid
                    if CoreAA(payload.data) then records = payload.data.infos
                    if type(records) = "roArray"
                        for each record in records
                            if CoreAA(record)
                                imdbId = CoreString(record.imdb_id)
                                if imdbId = "" and CoreAA(record.meta) then imdbId = CoreString(record.meta.imdb_id)
                                if createObject("roRegex", "^tt\d+$", "").isMatch(imdbId)
                                    state.records.push(record)
                                    if targets.doesExist(imdbId) and ApiMetadataArtwork(record) <> "" then illustrated[imdbId] = true
                                end if
                            end if
                        end for
                    else
                        state.complete = false
                    end if
                    if illustrated.count() >= 30 or m.auth = invalid then exit for
                end for
            end if
        end if
    end if
    ordered = []
    emitted = {}
    for each record in state.records
        imdbId = CoreString(record.imdb_id)
        if imdbId = "" and CoreAA(record.meta) then imdbId = CoreString(record.meta.imdb_id)
        if targets.doesExist(imdbId)
            key = kind + ":" + imdbId
            if ApiMetadataArtwork(m.metadata[key]) = "" then m.metadata[key] = record
            if ApiMetadataArtwork(m.metadata[key]) <> ""
                for each item in targets[imdbId]
                    if not emitted.doesExist(item.id)
                        ordered.push(item)
                        emitted[item.id] = true
                    end if
                end for
            end if
        end if
    end for
    ApiApplyMetadata(rows, kind)
    if preserveOrder then return rows
    state.preparedCount = rows.count()
    for each item in rows
        if not emitted.doesExist(item.id) and CoreSafeArtwork(item.artwork) <> ""
            ordered.push(item)
            emitted[item.id] = true
        end if
    end for
    for each item in rows
        if not emitted.doesExist(item.id) then ordered.push(item)
    end for
    return ordered
end function

sub ApiEnrich(items as object, kind as string)
    missing = []
    target = {}
    for each item in items
        imdbId = CoreString(item.imdbId)
        if createObject("roRegex", "^tt\d+$", "").isMatch(imdbId)
            key = kind + ":" + imdbId
            if not target.doesExist(imdbId)
                if ApiMetadataArtwork(m.metadata[key]) = "" and CoreNumber(m.metadataAttempts[key]) < 2 then missing.push(imdbId)
            end if
            target[imdbId] = item
        end if
    end for
    if missing.count() > 0
        for authAttempt = 0 to 1
            if not ApiMetadataAuth() then exit for
            headers = {Accept:"application/json", Authorization:m.auth.authorization, "X-API-PROFILE":m.auth.profile, "User-Agent":"okhttp/4.9.3", "X-APP-VERSION":"2.6.1"}
            path = "info/movie/"
            if kind = "series"
                path = "info/tvshows/"
                headers["X-API-Version"] = "V2"
            end if
            ids = ""
            for each id in missing
                if ids <> "" then ids += ","
                ids += id
            end for
            response = ApiHttp("https://dev.testbyte.top/api/" + path + ids, "GET", headers, "", 8000)
            unauthorized = response.code = 401 or response.code = 403
            if unauthorized then m.auth = invalid
            payload = ApiJson(response)
            if type(payload.data) = "roArray"
                for each imdbId in missing
                    key = kind + ":" + imdbId
                    m.metadataAttempts[key] = CoreNumber(m.metadataAttempts[key]) + 1
                end for
                for each record in payload.data
                    if CoreAA(record)
                        imdbId = CoreString(record.imdb_id)
                        if CoreAA(record.meta)
                            if imdbId = "" then imdbId = CoreString(record.meta.imdb_id)
                        end if
                        if target.doesExist(imdbId) then m.metadata[kind + ":" + imdbId] = record
                    end if
                end for
            end if
            if not unauthorized then exit for
        end for
    end if
    ApiApplyMetadata(items, kind)
end sub

sub ApiApplyMetadata(items as object, kind as string)
    for each item in items
        record = m.metadata[kind + ":" + CoreString(item.imdbId)]
        if CoreAA(record)
            if CoreString(record.title) <> "" then item.title = record.title
            if CoreAA(record.meta)
                if CoreString(record.title) = "" and CoreString(record.meta.title) <> "" then item.title = record.meta.title
                item.description = CoreString(record.meta.plot, CoreString(item.description))
                artwork = ApiMetadataArtwork(record)
                if artwork <> "" then item.artwork = artwork
            end if
            cached = m.lookup[item.id]
            if CoreAA(cached)
                cached.title = item.title
                cached.artwork = item.artwork
                cached.description = item.description
            end if
        end if
    end for
end sub

function ApiResolve(request as object, result as object) as object
    item = request.item
    if not CoreAA(item)
        result.ok = false
        result.message = "Select a playable title."
        return result
    end if
    cached = m.lookup[CoreString(item.id)]
    if not CoreAA(cached)
        kind = CoreString(item.kind)
        if kind = "movie"
            ApiLoadMovies()
        else if kind = "live"
            ApiLoadLive()
        else if kind = "episode"
            providerPage = int(CoreNumber(item.providerPage))
            if providerPage > 0 and providerPage <= 20 then ApiLoadSeriesPage(providerPage)
        end if
        cached = m.lookup[CoreString(item.id)]
    end if
    if not CoreAA(cached)
        result.ok = false
        result.message = "This title could not be matched to the current provider catalog. Browse the library and select it again."
        return result
    end if
    item = CorePublicItem(cached)
    if CoreString(item.id) = CoreString(request.item.id) and CoreString(item.artwork) = ""
        item.artwork = CoreSafeArtwork(request.item.artwork)
    end if
    if CoreString(item.url) = ""
        result.ok = false
        result.message = "This watched title could not be matched to the current provider catalog. Browse the library and select it again."
        return result
    end if
    format = CoreString(item.format)
    if format = ""
        headers = item.headers
        if not CoreAA(headers) then headers = {}
        response = ApiHttp(CoreString(item.url), "HEAD", headers, "", 10000)
        if response.ok
            contentType = ""
            for each key in response.headers
                if lcase(key) = "content-type" then contentType = lcase(CoreString(response.headers[key]))
            end for
            format = CoreFormat("", contentType)
        end if
    end if
    if format = "" or format = "ts"
        result.ok = false
        result.message = "The provider did not identify a stream format supported by this Roku. Try another title."
        return result
    end if
    item.format = format
    ApiDecorate(item)
    result.item = item
    return result
end function

function ApiGuide(request as object, result as object) as object
    if not m.connected
        result.ok = false
        result.message = "Connect your account to load its guide."
        return result
    end if
    if m.epg = invalid
        url = CoreString(m.credentials.epgUrl)
        if url = "" and CoreString(m.credentials.kind, "apollo") = "apollo"
            escape = createObject("roUrlTransfer")
            base = ApiTrimSlash(CoreString(m.credentials.baseUrl, "https://tvnow.best"))
            url = base + "/api/epg/" + escape.escape(CoreString(m.credentials.username)) + "/" + escape.escape(CoreString(m.credentials.password)) + "/lite.xml.gz"
        end if
        if url = ""
            result.message = "This account has no EPG URL configured."
            return result
        end if
        response = ApiHttp(url, "GET", {"Accept-Encoding":"gzip, deflate"}, "", 15000)
        if not response.ok
            result.message = "The guide could not load. Live TV remains available."
            return result
        end if
        xml = createObject("roXMLElement")
        if not xml.parse(response.body)
            result.message = "The provider guide is compressed or unavailable in a readable XMLTV format. Live TV remains available."
            return result
        end if
        m.epg = []
        for each programme in xml.getNamedElements("programme")
            attrs = programme.getAttributes()
            titleNodes = programme.getNamedElements("title")
            if titleNodes.count() > 0
                start = ApiXmlDate(CoreString(attrs.start))
                finish = ApiXmlDate(CoreString(attrs.stop))
                if start > 0 and finish > start
                    description = ""
                    descNodes = programme.getNamedElements("desc")
                    if descNodes.count() > 0 then description = descNodes[0].getText()
                    m.epg.push({id:CoreString(attrs.channel) + ":" + start.toStr(), kind:"program", channelId:CoreString(attrs.channel), title:titleNodes[0].getText(), description:description, startsAt:start, endsAt:finish})
                end if
            end if
        end for
    end if
    channel = request.channel
    key = ""
    if CoreAA(channel)
        key = CoreString(channel.tvgId)
        if key = "" then key = CoreString(channel.tvgName)
        if key = "" then key = CoreString(channel.title)
    end if
    rows = []
    now = ApiNow()
    for each programme in m.epg
        if programme.channelId = key and programme.endsAt > now then rows.push(programme)
    end for
    rows.sortBy("startsAt")
    result.total = rows.count()
    result.hasMore = rows.count() > 8
    for each programme in rows
        date = createObject("roDateTime")
        date.fromSeconds(programme.startsAt)
        date.toLocalTime()
        programme.startText = date.getHours().toStr() + ":" + right("0" + date.getMinutes().toStr(), 2)
        result.items.push(programme)
        if result.items.count() >= 8 then exit for
    end for
    if rows.count() = 0 then result.message = "No upcoming guide listings are available for this channel."
    return result
end function

function ApiXmlDate(value as string) as double
    matched = createObject("roRegex", "^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-])(\d{2})(\d{2}))?", "").match(value)
    if matched.count() < 7 then return 0.0#
    iso = matched[1] + "-" + matched[2] + "-" + matched[3] + "T" + matched[4] + ":" + matched[5] + ":" + matched[6] + "Z"
    date = createObject("roDateTime")
    date.fromISO8601String(iso)
    stamp = date.asSeconds() * 1.0#
    if matched.count() >= 10
        if matched[7] <> ""
            offset = (val(matched[8]) * 60 + val(matched[9])) * 60
            if matched[7] = "+" then stamp -= offset else stamp += offset
        end if
    end if
    return stamp
end function
