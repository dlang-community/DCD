.PHONY: all

all: dmd
dmd: dmdserver dmdclient
debug: dmdclient debugserver
gdc: gdcserver gdcclient
ldc: ldcserver ldcclient

DMD = dmd
GDC = gdc
LDC = ldc2

report:
	dscanner --report src > dscanner-report.json
	sonar-runner

clean:
	rm -rf bin
	rm -f dscanner-report.json

CLIENT_SRC = src/client.d\
	src/messages.d\
	src/stupidlog.d\
	src/dcd_version.d\
	msgpack-d/src/msgpack.d

DMD_CLIENT_FLAGS = -Imsgpack-d/src\
	-Imsgpack-d/src\
	-release\
	-inline\
	-O\
	-wi\
	-ofbin/dcd-client

GDC_CLIENT_FLAGS =  -Imsgpack-d/src\
	-O3\
	-frelease\
	-obin/dcd-client

LDC_CLIENT_FLAGS = -Imsgpack-d/src\
	-Imsgpack-d/src\
	-release\
	-O5\
	-oq\
	-of=bin/dcd-client

SERVER_SRC = src/actypes.d\
	src/conversion/astconverter.d\
	src/conversion/first.d\
	src/conversion/second.d\
	src/conversion/third.d\
	src/autocomplete.d\
	src/constants.d\
	src/messages.d\
	src/modulecache.d\
	src/semantic.d\
	src/server.d\
	src/stupidlog.d\
	src/string_interning.d\
	src/dcd_version.d\
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
	containers/src/containers/internal/storage_type.d\
	containers/src/containers/slist.d\
	msgpack-d/src/msgpack.d

DMD_SERVER_FLAGS = -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-wi\
	-O\
	-release\
	-inline\
	-ofbin/dcd-server

DEBUG_SERVER_FLAGS = -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-wi\
	-g\
	-ofbin/dcd-server

GDC_SERVER_FLAGS =  -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-O3\
	-frelease\
	-obin/dcd-server

LDC_SERVER_FLAGS = -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-O5\
	-release\
	-oq\
	-of=bin/dcd-server

dmdclient:
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${CLIENT_SRC} ${DMD_CLIENT_FLAGS}

dmdserver:
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${SERVER_SRC} ${DMD_SERVER_FLAGS}

debugserver:
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${SERVER_SRC} ${DEBUG_SERVER_FLAGS}


gdcclient:
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${GDC} ${CLIENT_SRC} ${GDC_CLIENT_FLAGS}

gdcserver:
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${GDC} ${SERVER_SRC} ${GDC_SERVER_FLAGS}

ldcclient:
	${LDC} ${CLIENT_SRC} ${LDC_CLIENT_FLAGS}

ldcserver:
	${LDC} ${SERVER_SRC} ${LDC_SERVER_FLAGS}
