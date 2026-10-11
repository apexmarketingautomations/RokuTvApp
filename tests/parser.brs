sub Main()
    m.failures = 0
    fixture = readAsciiFile("pkg:/parser_compat.m3u")
    expected = parseJson(readAsciiFile("pkg:/parser_compat.json"))
    for each kind in ["movie", "episode", "live"]
        parsed = CoreParseM3U(fixture, kind)
        Check(formatJson(parsed) = formatJson(expected[kind]), "all catalog fields and historical IDs match the pre-optimization fixture")
    end for
    corpus = parseJson(readAsciiFile("pkg:/comma_corpus.json"))
    for each line in corpus
        Check(CoreMetadataComma(line) = ReferenceMetadataComma(line), "quoted and escaped comma positions match the original parser")
    end for
    Check(CoreDecode("  Ordinary title  ") = "Ordinary title", "ordinary metadata still trims whitespace")
    Check(CoreDecode(" &quot;Title&quot; &amp; &#39;quote&#39; &lt;all&gt; ") = chr(34) + "Title" + chr(34) + " & 'quote' <all>", "entity decoding retains all supported replacements")

    q = chr(34)
    line = "#EXTINF:-1 tvg-id=" + q + "tt10000001" + q + " tvg-name=" + q + "Sample Provider Movie (2026)" + q + " group-title=" + q + "Recent Added" + q + ",Sample Provider Movie (2026)"
    timer = createObject("roTimespan")
    timer.mark()
    for i = 1 to 200
        ReferenceMetadataComma(line)
    end for
    referenceMillis = timer.totalMilliseconds()
    timer.mark()
    for i = 1 to 200
        CoreMetadataComma(line)
    end for
    optimizedMillis = timer.totalMilliseconds()
    Check(optimizedMillis * 100 < referenceMillis * 70, "catalog delimiter parsing avoids the slow character-by-character walk")
    print "COMMA BENCHMARK reference_ms=";referenceMillis;" optimized_ms=";optimizedMillis
    if m.failures = 0 then print "PARSER TESTS PASSED" else print "PARSER TESTS FAILED: ";m.failures
end sub

' Frozen compatibility/performance reference from the previous implementation.
function ReferenceMetadataComma(line as string) as integer
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

sub Check(condition as boolean, label as string)
    if not condition
        m.failures += 1
        print "FAIL: ";label
    end if
end sub
