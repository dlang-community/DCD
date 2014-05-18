rm -f containers/src/std/allocator.d

dmd\
	client.d\
	messages.d\
	stupidlog.d\
	msgpack-d/src/msgpack.d\
	-Imsgpack-d/src\
	-release -inline -O -wi\
	-ofdcd-client

dmd\
	actypes.d\
	conversion/astconverter.d\
	conversion/first.d\
	conversion/second.d\
	conversion/third.d\
	autocomplete.d\
	constants.d\
	messages.d\
	modulecache.d\
	semantic.d\
	server.d\
	stupidlog.d\
	string_interning.d\
	dscanner/std/d/ast.d\
	dscanner/std/d/entities.d\
	dscanner/std/d/lexer.d\
	dscanner/std/d/parser.d\
	dscanner/std/lexer.d\
	dscanner/std/allocator.d\
	dscanner/formatter.d\
	containers/src/memory/allocators.d\
	containers/src/memory/appender.d\
	containers/src/containers/dynamicarray.d\
	containers/src/containers/ttree.d\
	containers/src/containers/unrolledlist.d\
	containers/src/containers/hashset.d\
	containers/src/containers/internal/hash.d\
	containers/src/containers/slist.d\
	msgpack-d/src/msgpack.d\
	-Icontainers/src\
	-Imsgpack-d/src\
	-Idscanner\
	-wi -O -release\
	-ofdcd-server

#gdc client.d\
#	messages.d\
#	msgpack-d/src/msgpack.d\
#	-Imsgpack-d/src\
#	-O3 -frelease -fno-bounds-check\
#	-odcd-client
#
#gdc \
#	actypes.d\
#	astconverter.d\
#	autocomplete.d\
#	constants.d\
#	messages.d\
#	modulecache.d\
#	semantic.d\
#	server.d\
#	stupidlog.d\
#	dscanner/stdx/d/ast.d\
#	dscanner/stdx/d/parser.d\
#	dscanner/stdx/lexer.d\
#	dscanner/stdx/d/lexer.d\
#	dscanner/stdx/d/entities.d\
#	dscanner/formatter.d\
#	msgpack-d/src/msgpack.d\
#	-Imsgpack-d/src\
#	-Idscanner\
#	-O3 -frelease -fno-bounds-check\
#	-odcd-server

