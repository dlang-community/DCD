del /f containers\src\std\allocator.d

dmd^
 src\client.d^
 src\messages.d^
 src\stupidlog.d^
 src\dcd_version.d^
 msgpack-d/src/msgpack.d^
 -Imsgpack-d/src^
 -release -inline -O -wi^
 -ofdcd-client

dmd^
 src\actypes.d^
 src\conversion/package.d^
 src\conversion/first.d^
 src\conversion/second.d^
 src\conversion/third.d^
 src\autocomplete.d^
 src\constants.d^
 src\messages.d^
 src\modulecache.d^
 src\semantic.d^
 src\server.d^
 src\stupidlog.d^
 src\string_interning.d^
 src\dcd_version.d^
 libdparse/src/std/d/ast.d^
 libdparse/src/std/d/entities.d^
 libdparse/src/std/d/lexer.d^
 libdparse/src/std/d/parser.d^
 libdparse/src/std/lexer.d^
 libdparse/src/std/allocator.d^
 libdparse/src/std/d/formatter.d^
 containers/src/memory/allocators.d^
 containers/src/memory/appender.d^
 containers/src/containers/dynamicarray.d^
 containers/src/containers/ttree.d^
 containers/src/containers/unrolledlist.d^
 containers/src/containers/hashset.d^
 containers/src/containers/internal/hash.d^
 containers/src/containers/internal/node.d^
 containers/src/containers/internal/storage_type.d^
 containers/src/containers/slist.d^
 msgpack-d/src/msgpack.d^
 -Icontainers/src^
 -Imsgpack-d/src^
 -Ilibdparse/src^
 -wi -O -release^
 -ofdcd-server

