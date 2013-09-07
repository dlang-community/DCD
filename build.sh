dmd -wi client.d messages.d msgpack-d/src/msgpack.d -Imsgpack-d/src -ofdcd-client
dmd -wi -g server.d modulecache.d actypes.d messages.d constants.d acvisitor.d autocomplete.d dscanner/stdx/d/ast.d dscanner/stdx/d/parser.d dscanner/stdx/d/lexer.d dscanner/stdx/d/entities.d msgpack-d/src/msgpack.d dscanner/formatter.d -Imsgpack-d/src -Idscanner/ -ofdcd-server
