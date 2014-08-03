.PHONY: all

all: dmd
dmd: dmdserver dmdclient
gdc: gdcserver gdcclient
#ldc: ldcserver ldcclient

DMD = dmd
GDC = gdc
#LDC = ldc

CLIENT_SRC = client.d\
	messages.d\
	stupidlog.d\
	msgpack-d/src/msgpack.d

DMD_CLIENT_FLAGS = -Imsgpack-d/src\
	-Imsgpack-d/src\
	-release\
	-inline\
	-O\
	-wi\
	-ofdcd-client

GDC_CLIENT_FLAGS =  -Imsgpack-d/src\
	-O3\
	-frelease\
	-odcd-client

SERVER_SRC = actypes.d\
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
	libdparse/src/std/d/ast.d\
	libdparse/src/std/d/entities.d\
	libdparse/src/std/d/lexer.d\
	libdparse/src/std/d/parser.d\
	libdparse/src/std/lexer.d\
	libdparse/src/std/allocator.d\
	libdparse/src/std/d/formatter.d\
	containers/src/memory/allocators.d\
	containers/src/memory/appender.d\
	containers/src/containers/dynamicarray.d\
	containers/src/containers/ttree.d\
	containers/src/containers/unrolledlist.d\
	containers/src/containers/hashset.d\
	containers/src/containers/internal/hash.d\
	containers/src/containers/internal/node.d\
	containers/src/containers/slist.d\
	msgpack-d/src/msgpack.d

DMD_SERVER_FLAGS = -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-wi\
	-O\
	-release\
	-inline\
	-ofdcd-server

GDC_SERVER_FLAGS =  -Imsgpack-d/src\
	-Ilibdparse/src\
	-O3\
	-frelease\
	-odcd-server

dmdclient:
	rm -f containers/src/std/allocator.d
	${DMD} ${CLIENT_SRC} ${DMD_CLIENT_FLAGS}

dmdserver:
	rm -f containers/src/std/allocator.d
	${DMD} ${SERVER_SRC} ${DMD_SERVER_FLAGS}

gdcclient:
	rm -f containers/src/std/allocator.d
	${GDC} {CLIENT_SRC} ${GDC_CLIENT_FLAGS}

gdcserver:
	rm -f containers/src/std/allocator.d
	${GDC} {SERVER_SRC} ${GDC_SERVER_FLAGS}

#ldcclient:
#	${LDC} {CLIENT_SRC} ${LDC_CLIENT_FLAGS}
#
#ldcserver:
#	${LDC} {SERVER_SRC} ${LDC_SERVER_FLAGS}
