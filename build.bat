dmd -wi client.d messages.d msgpack-d/src/msgpack.d -Imsgpack-d/src -release -inline -noboundscheck -O -ofdcd-client.exe
dmd actypes.d astconverter.d autocomplete.d constants.d messages.d modulecache.d semantic.d server.d stupidlog.d dscanner/stdx/d/ast.d dscanner/stdx/d/parser.d dscanner/stdx/lexer.d dscanner/stdx/d/lexer.d dscanner/stdx/d/entities.d dscanner/formatter.d datapicked/dpick/buffer/buffer.d datapicked/dpick/buffer/traits.d msgpack-d/src/msgpack.d -Imsgpack-d/src -Idscanner -Idatapicked -wi -g -ofdcd-server.exe
	
