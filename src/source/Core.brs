' Pure catalog and persistence helpers shared by the worker and executable tests.
function CoreString(value as dynamic, fallback = "" as string) as string
    if type(value) = "String" or type(value) = "roString" then return value
    return fallback
end function

function CoreNumber(value as dynamic, fallback = 0 as dynamic) as dynamic
    if value = invalid then return fallback
    kind = type(value)
    if kind = "Integer" or kind = "roInt" or kind = "LongInteger" or kind = "Float" or kind = "roFloat" or kind = "Double" or kind = "roDouble" then return value
    if kind = "String" or kind = "roString"
        value = value.trim()
        if createObject("roRegex", "^-?[0-9]+(?:\.[0-9]+)?$", "").isMatch(value) then return val(value)
    end if
    return fallback
end function

function CoreAA(value as dynamic) as boolean
    return type(value) = "roAssociativeArray"
end function

function CoreDecode(value as string) as string
    value = value.replace("&amp;", "&").replace("&quot;", chr(34)).replace("&#39;", "'")
    return value.replace("&lt;", "<").replace("&gt;", ">").trim()
end function

function CoreIdentity(value as string) as string
    ' Bounded arithmetic avoids signed integer overflow on the interpreter/device.
    hash = 7.0#
    for i = 1 to len(value)
        nextValue = hash * 31 + asc(mid(value, i, 1))
        hash = nextValue - int(nextValue / 10000019) * 10000019
    end for
    prefix = createObject("roRegex", "[^a-z0-9]+", "i").replaceAll(lcase(value), "-")
    return left(prefix, 64) + "-" + str(int(hash)).trim()
end function

function CoreAttrs(line as string) as object
    attrs = {}
    q = chr(34)
    pattern = "([A-Za-z0-9_-]+)\s*=\s*(" + q + "([^" + q + "]*)" + q + "|'([^']*)'|([^\s]+))"
    expression = createObject("roRegex", pattern, "")
    remaining = line
    while expression.isMatch(remaining)
        parts = expression.match(remaining)
        raw = parts[3]
        if raw = "" then raw = parts[4]
        if raw = "" then raw = parts[5]
        attrs[lcase(parts[1])] = CoreDecode(raw)
        offset = instr(1, remaining, parts[0])
        remaining = mid(remaining, offset + len(parts[0]))
    end while
    return attrs
end function

function CoreMetadataComma(line as string) as integer
    quote = ""
    escaped = false
    for i = 1 to len(line)
        character = mid(line, i, 1)
        if character = "\" and not escaped
            escaped = true
        else
            if not escaped
                if character = chr(34) or character = "'"
                    if quote = character
                        quote = ""
                    else if quote = ""
                        quote = character
                    end if
                else if character = "," and quote = ""
                    return i
                end if
            end if
            escaped = false
        end if
    end for
    return 0
end function

function CoreFormat(url as string, hint = "" as string) as string
    hint = lcase(hint)
    if instr(1, hint, "mpegurl") > 0 or hint = "hls" or hint = "m3u8" then return "hls"
    if instr(1, hint, "dash") > 0 then return "dash"
    if hint = "mp4" or hint = "video/mp4" then return "mp4"
    if hint = "mpegts" or hint = "video/mp2t" then return "ts"
    path = lcase(createObject("roRegex", "[?#].*$", "").replace(url, ""))
    if right(path, 5) = ".m3u8" then return "hls"
    if right(path, 4) = ".mpd" then return "dash"
    if right(path, 4) = ".mp4" or right(path, 4) = ".m4v" or right(path, 4) = ".mov" then return "mp4"
    if right(path, 3) = ".ts" then return "ts"
    if right(path, 4) = ".mkv" then return "mkv"
    return ""
end function

function CoreSafeArtwork(value as dynamic) as string
    url = CoreString(value).trim()
    if left(url, 2) = "//" then url = "https:" + url
    if left(lcase(url), 8) <> "https://" then return ""
    if createObject("roRegex", "^https://[^/]*@", "i").isMatch(url) then return ""
    if createObject("roRegex", "[?&][^=&]*(auth|credential|key|password|secret|signature|token|user)[^=&]*=", "i").isMatch(url) then return ""
    fragment = instr(1, url, "#")
    if fragment > 0 then url = left(url, fragment - 1)
    return url
end function

function CoreParseM3U(text as string, kind as string) as object
    items = []
    counts = {}
    pending = invalid
    for each raw in text.split(chr(10))
        line = raw.trim()
        if left(ucase(line), 8) = "#EXTINF:"
            comma = CoreMetadataComma(line)
            title = ""
            metadata = line
            if comma > 0
                title = CoreDecode(mid(line, comma + 1))
                metadata = left(line, comma - 1)
            end if
            attrs = CoreAttrs(metadata)
            if title = "" then title = CoreString(attrs["tvg-name"], "Untitled provider entry")
            pending = {title:title, attrs:attrs, headers:{}}
        else if pending <> invalid
            if left(ucase(line), 8) = "#EXTGRP:"
                if CoreString(pending.attrs["group-title"]) = "" then pending.attrs["group-title"] = mid(line, 9).trim()
            else if left(lcase(line), 27) = "#extvlcopt:http-user-agent="
                pending.headers["User-Agent"] = mid(line, 28).trim()
            else if left(lcase(line), 25) = "#extvlcopt:http-referrer="
                pending.headers["Referer"] = mid(line, 26).trim()
            else if left(lcase(line), 9) = "#exthttp:"
                headers = parseJson(mid(line, 10))
                if CoreAA(headers)
                    for each header in headers
                        if CoreString(headers[header]) <> "" then pending.headers[header] = headers[header]
                    end for
                end if
            else if line <> "" and left(line, 1) <> "#"
                if left(lcase(line), 7) = "http://" or left(lcase(line), 8) = "https://"
                    attrs = pending.attrs
                    tvgId = CoreString(attrs["tvg-id"])
                    tvgName = CoreString(attrs["tvg-name"])
                    category = CoreString(attrs["group-title"], "Uncategorized")
                    providerName = tvgName
                    if providerName = "" then providerName = pending.title
                    identityText = tvgId + "|" + tvgName + "|" + providerName + "|" + category
                    ' Apollo repeats tvg-name and tvg-id across episodes and pages.
                    ' Include the actual episode label; page-local duplicate indices are insufficient.
                    if kind = "episode" then identityText += "|" + pending.title
                    identity = CoreIdentity(identityText)
                    duplicate = CoreNumber(counts[identity]) + 1
                    counts[identity] = duplicate
                    id = kind + "-" + identity
                    if duplicate > 1 then id += "-" + str(int(duplicate)).trim()
                    poster = CoreString(attrs["tvg-logo"])
                    if poster = "" then poster = CoreString(attrs.logo)
                    if poster = "" then poster = CoreString(attrs.poster)
                    if poster = "" then poster = CoreString(attrs["movie-image"])
                    if poster <> ""
                        if left(poster, 1) = "/" and left(poster, 2) <> "//"
                            origin = createObject("roRegex", "^(https?://[^/]+)", "i").match(line)
                            if origin.count() > 1 then poster = origin[1] + poster
                        end if
                    end if
                    hint = CoreString(attrs["stream-format"])
                    if hint = "" then hint = CoreString(attrs["mime-type"])
                    if hint = "" then hint = CoreString(attrs.type)
                    format = CoreFormat(line, hint)
                    if kind = "live" and format = "" then format = "hls"
                    items.push({id:id, kind:kind, title:pending.title, category:category, url:line, format:format, headers:pending.headers, artwork:CoreSafeArtwork(poster), description:"", imdbId:tvgId, tvgId:tvgId, tvgName:tvgName})
                end if
                pending = invalid
            end if
        end if
    end for
    return items
end function

function CoreSeriesInfo(item as object) as object
    title = CoreString(item.title)
    matcher = createObject("roRegex", "\bS(\d{1,3})[ ._-]*E(\d{1,3})\b", "i")
    if not matcher.isMatch(title) then matcher = createObject("roRegex", "\b(\d{1,3})x(\d{1,3})\b", "i")
    season = 0
    episode = 0
    if matcher.isMatch(title)
        matched = matcher.match(title)
        season = val(matched[1])
        episode = val(matched[2])
        location = instr(1, title, matched[0])
        if location > 1
            title = createObject("roRegex", "[ ._-]+$", "").replace(left(title, location - 1), "").trim()
        end if
    end if
    return {title:title, season:season, episode:episode}
end function

function CoreBuildSeries(rows as object) as object
    groups = {}
    shows = []
    for each item in rows
        info = CoreSeriesInfo(item)
        providerId = CoreString(item.imdbId)
        if providerId = "" then providerId = CoreString(item.tvgId)
        if providerId <> ""
            key = "series-provider-" + CoreIdentity(providerId)
        else
            key = "series-title-" + CoreIdentity(lcase(info.title))
        end if
        if not groups.doesExist(key)
            category = CoreString(item.category, "TV Shows")
            if category = info.title then category = "TV Shows"
            show = {id:key, kind:"series", title:info.title, sortKey:lcase(info.title), category:category, artwork:CoreString(item.artwork), description:"", imdbId:CoreString(item.imdbId), episodes:[], url:"", format:""}
            groups[key] = show
            shows.push(show)
        end if
        item.seriesId = key
        item.season = info.season
        item.episode = info.episode
        item.sortKey = info.season * 10000 + info.episode
        groups[key].episodes.push(item)
    end for
    shows.sortBy("sortKey")
    for each show in shows
        show.episodes.sortBy("sortKey")
    end for
    return shows
end function

function CorePublicItem(item as object) as object
    result = {}
    for each field in ["id", "kind", "title", "category", "artwork", "description", "imdbId", "url", "format", "headers", "seriesId", "season", "episode", "providerPage", "tvgId", "tvgName", "resumePosition", "favorite"]
        if item.doesExist(field) then result[field] = item[field]
    end for
    return result
end function

function CorePage(rows as object, category as string, query as string, page as integer) as object
    if page < 0 then page = 0
    query = lcase(query.trim())
    filtered = []
    for each item in rows
        include = true
        if category <> "All" and category <> "" then include = CoreString(item.category) = category
        if query <> ""
            searchText = lcase(CoreString(item.title) + " " + CoreString(item.category))
            if instr(1, searchText, query) = 0 then include = false
        end if
        if include then filtered.push(item)
    end for
    items = []
    start = page * 30
    if start < filtered.count()
        finish = start + 29
        if finish >= filtered.count() then finish = filtered.count() - 1
        for i = start to finish
            items.push(CorePublicItem(filtered[i]))
        end for
    end if
    return {items:items, total:filtered.count(), hasMore:start + items.count() < filtered.count(), page:page}
end function

function CoreCategories(rows as object) as object
    values = []
    seen = {all:true}
    for each item in rows
        category = CoreString(item.category)
        if category <> "" and not seen.doesExist(lcase(category))
            seen[lcase(category)] = true
            values.push(category)
        end if
    end for
    values.sort("i")
    values.unshift("All")
    return values
end function

function CoreProgress(item as object, position as float, duration as float, stamp as double) as object
    if position < 0 then position = 0
    if duration < 0 then duration = 0
    if duration > 0
        if position >= duration - 30 or position >= duration * 0.95 then position = 0
    end if
    if CoreString(item.kind) = "live" then position = 0
    artwork = CoreSafeArtwork(item.artwork)
    if len(artwork) > 256 then artwork = ""
    snapshot = {title:left(CoreString(item.title), 120), artwork:artwork, category:left(CoreString(item.category), 40)}
    for each field in ["seriesId", "season", "episode", "providerPage"]
        if item.doesExist(field) then snapshot[field] = item[field]
    end for
    return {id:CoreString(item.id), kind:CoreString(item.kind), position:position, duration:duration, updatedAt:stamp, snapshot:snapshot}
end function

function CoreValidSession(session as dynamic) as boolean
    if not CoreAA(session) then return false
    if not createObject("roRegex", "^\d{6}$", "").isMatch(CoreString(session.code)) then return false
    if CoreString(session.pollToken) = "" then return false
    if left(CoreString(session.setupUrl), 8) <> "https://" then return false
    return CoreNumber(session.expiresAt) > 0
end function
