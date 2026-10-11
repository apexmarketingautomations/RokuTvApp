sub init()
    m.art = m.top.findNode("art")
    m.title = m.top.findNode("title")
    m.border = m.top.findNode("border")
end sub

sub contentChanged()
    content = m.top.itemContent
    if content = invalid then return
    m.title.text = content.title
    m.art.uri = content.hdPosterUrl
end sub

sub focusChanged()
    if m.top.focusPercent > 0.5 and m.top.rowFocusPercent > 0.5 then
        m.border.color = "0x72F6FFFF"
    else
        m.border.color = "0x36CFEA99"
    end if
end sub
