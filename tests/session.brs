sub Main()
    m.failures = 0
    ApiResetMemory()
    ' The interpreter has no roRegistrySection or HTTP transport. Keep their
    ' state in boundary doubles while exercising the real worker dispatch.
    saved = {kind:"m3u", playlistUrl:"https://provider.example.test/library.m3u8"}
    m.registry = SessionRegistry(saved)
    m.httpCalls = 0
    m.httpResponses = []
    restored = ApiDispatch({id:1, op:"restore"})
    Check(restored.ok and restored.connected, "saved account restores while the provider is unreachable")
    Check(m.httpCalls = 0, "reopening the app does not wait for the provider to authenticate saved credentials again")
    Check(m.registry.exists("credentials"), "restoring the account preserves stored credentials")
    Check(restored.continue.count() = 1, "saved viewing history restores before catalog networking")
    Check(m.favorites.doesExist("saved-live"), "saved favorites survive account restoration")

    m.httpResponses = [{ok:false, code:503, body:"", headers:{}}]
    unavailable = ApiDispatch({id:2, op:"catalog", kind:"live"})
    Check(not unavailable.ok and unavailable.connected, "an unavailable live catalog reports failure without signing out")
    Check(m.registry.exists("credentials"), "catalog failure does not remove saved credentials")

    playlist = "#EXTM3U" + chr(10) + "#EXTINF:-1,Fixture Channel" + chr(10) + "https://stream.example.test/live.m3u8"
    m.httpResponses = [{ok:true, code:200, body:playlist, headers:{}}]
    recovered = ApiDispatch({id:3, op:"catalog", kind:"live"})
    Check(recovered.ok and recovered.connected, "live catalog retries with saved credentials after provider recovery")
    Check(recovered.items.count() = 1, "recovered live catalog reaches the app")
    if recovered.items.count() = 1
        Check(recovered.items[0].title = "Fixture Channel", "lazy load uses the returned provider catalog")
        Check(m.lookup.doesExist(recovered.items[0].id), "lazy live load indexes streams for playback")
    end if
    beforeCached = m.httpCalls
    cached = ApiDispatch({id:4, op:"catalog", kind:"live"})
    Check(cached.items.count() = 1 and m.httpCalls = beforeCached, "live navigation reuses the loaded catalog")

    restoredAgain = ApiDispatch({id:5, op:"restore"})
    Check(restoredAgain.connected and m.httpCalls = beforeCached, "a later app restart still restores without a network check")
    if recovered.items.count() = 1 then m.favorites[recovered.items[0].id] = true
    m.httpResponses = [{ok:true, code:200, body:playlist, headers:{}}]
    favorites = ApiDispatch({id:6, op:"catalog", kind:"favorites"})
    Check(favorites.ok and favorites.items.count() = 1, "favorites lazily reload live inventory after restart")

    ApiDispatch({id:7, op:"restore"})
    m.httpResponses = [{ok:true, code:200, body:playlist, headers:{}}]
    allItems = ApiDispatch({id:8, op:"catalog", kind:"all"})
    Check(allItems.ok and allItems.items.count() = 1, "all-catalog search includes live inventory after restart")

    signedOut = ApiDispatch({id:9, op:"signout"})
    Check(signedOut.ok and not signedOut.connected, "explicit signout clears the active session")
    Check(not m.registry.exists("credentials"), "explicit signout removes saved credentials")
    afterSignout = ApiDispatch({id:10, op:"restore"})
    Check(not afterSignout.connected, "explicit signout remains signed out after restart")

    m.registry = SessionRegistry({kind:"apollo", username:"fixture-user", password:"fixture-password", baseUrl:"https://provider.example.test"})
    beforeApollo = m.httpCalls
    apollo = ApiDispatch({id:11, op:"restore"})
    Check(apollo.ok and apollo.connected, "a saved Apollo account restores without entering credentials again")
    Check(m.httpCalls = beforeApollo, "Apollo restoration requires no network response")
    if CoreAA(m.credentials)
        Check(m.credentials.username = "fixture-user", "saved Apollo credentials remain available to provider requests")
    else
        Check(false, "Apollo restoration restores provider credentials")
    end if

    for each invalidAccount in [{}, {kind:"apollo", username:"fixture-user"}, {kind:"m3u", playlistUrl:""}]
        m.registry = SessionRegistry(invalidAccount)
        incomplete = ApiDispatch({id:12, op:"restore"})
        Check(not incomplete.connected, "incomplete stored account does not masquerade as a signed-in session")
    end for

    if m.failures = 0
        print "SESSION TESTS PASSED"
    else
        print "SESSION TESTS FAILED: "; m.failures
    end if
end sub

function SessionRegistry(credentials as object) as object
    return {
        values:{
            credentials:formatJson(credentials)
            progress:formatJson({"saved-movie":{id:"saved-movie", kind:"movie", position:120, duration:1000, updatedAt:1, snapshot:{title:"Saved Movie", artwork:"", category:"Drama"}}})
            favorites:formatJson({"saved-live":true})
        }
        read:function(key as string) as string
            if m.values.doesExist(key) then return m.values[key]
            ' JSON null yields the same missing value without interpreter warnings.
            return "null"
        end function
        write:function(key as string, value as string) as boolean
            m.values[key] = value
            return true
        end function
        flush:function() as boolean
            return true
        end function
        delete:function(key as string) as boolean
            m.values.delete(key)
            return true
        end function
        exists:function(key as string) as boolean
            return m.values.doesExist(key)
        end function
    }
end function

function ApiHttp(url as string, method as string, headers as object, body as string, timeout as integer) as object
    m.httpCalls += 1
    Check(url = "https://provider.example.test/library.m3u8" and method = "GET", "lazy live catalog requests the saved provider playlist")
    if m.httpResponses.count() = 0 then return {ok:false, code:503, body:"", headers:{}}
    return m.httpResponses.shift()
end function

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: "; label
    end if
end sub
