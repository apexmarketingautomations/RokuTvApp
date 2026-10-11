sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("ApexScene")
    scene.ObserveField("exitRequested", port)
    screen.Show()
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" then
            if msg.IsScreenClosed() then return
        else if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "exitRequested" then
                if msg.GetData() then
                    screen.Close()
                    return
                end if
            end if
        end if
    end while
end sub
