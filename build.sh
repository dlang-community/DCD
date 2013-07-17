dmd client.d messages.d msgpack-d/src/msgpack.d -Imsgpack-d/src -ofdcd-client
dmd server.d messages.d constants.d importutils.d autocomplete.d ../dscanner/std/d/ast.d ../dscanner/std/d/parser.d ../dscanner/std/d/lexer.d ../dscanner/std/d/entities.d msgpack-d/src/msgpack.d -Imsgpack-d/src -I../dscanner/ -ofdcd-server
