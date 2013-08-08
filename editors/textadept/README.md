#Textadept Integration

###Installation
1. Copy the dcd.lua file into your ~/.textadept/modules/dmd/ folder
2. Modify your ~/.textadept/modules/dmd/init.lua file:

    1. Require the dcd module

        _M.dcd = require "dmd.dcd"

    2. Register the autocomplete function

            events.connect(events.CHAR_ADDED, function(ch)
                _M.dcd.autocomplete(ch)
            end)
