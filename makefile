.PHONY: all

all: dmd
dmd: dmdserver dmdclient
debug: dmdclient debugserver
gdc: gdcserver gdcclient
ldc: ldcserver ldcclient

DMD := dmd
GDC := gdc
LDC := ldc2

OBJ_DIR := objs

githash:
	git log -1 --format="%H" > githash.txt

report:
	dscanner --report src > dscanner-report.json
	sonar-runner

clean:
	rm -rf bin
	rm -f dscanner-report.json
	rm -f githash.txt
	rm -f *.o
	rm -rf $(OBJ_DIR)

CLIENT_SRC := src/client.d\
	src/messages.d\
	src/stupidlog.d\
	src/dcd_version.d\
	msgpack-d/src/msgpack.d

DMD_CLIENT_FLAGS := -Imsgpack-d/src\
	-Imsgpack-d/src\
	-J.\
	-release\
	-inline\
	-O\
	-wi\
	-ofbin/dcd-client

GDC_CLIENT_FLAGS := -Imsgpack-d/src\
	-J.\
	-O3\
	-frelease\
	-obin/dcd-client

LDC_CLIENT_FLAGS := -Imsgpack-d/src\
	-Imsgpack-d/src\
	-J=.\
	-release\
	-O5\
	-oq\
	-of=bin/dcd-client

SERVER_SRC := src/actypes.d\
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

SERVER_OBJS = $(SERVER_SRC:%.d=$(OBJ_DIR)/%.o)

DMD_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-J.\
	-wi\
	-O\
	-release\
	-inline\
	-ofbin/dcd-server

DEBUG_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-wi\
	-g\
	-ofbin/dcd-server\
	-J.

GDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-J.\
	-O3\
	-frelease\
	-obin/dcd-server

LDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-Ilibdparse/src\
	-Isrc\
	-J=.\
	-O5\
	-release\

dmdclient: githash
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${CLIENT_SRC} ${DMD_CLIENT_FLAGS}

dmdserver: githash
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${SERVER_SRC} ${DMD_SERVER_FLAGS}

debugserver: githash
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${DMD} ${SERVER_SRC} ${DEBUG_SERVER_FLAGS}

gdcclient: githash
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${GDC} ${CLIENT_SRC} ${GDC_CLIENT_FLAGS}

gdcserver: githash
	mkdir -p bin
	rm -f containers/src/std/allocator.d
	${GDC} ${SERVER_SRC} ${GDC_SERVER_FLAGS}

ldcclient: githash
	${LDC} ${CLIENT_SRC} ${LDC_CLIENT_FLAGS}

$(OBJ_DIR)/%.o: $(SERVER_SRC)
	$(LDC) $*.d $(LDC_SERVER_FLAGS) -od=$(OBJ_DIR) -op -c

ldcserver: githash $(SERVER_OBJS)
	${LDC} ${SERVER_OBJS} ${LDC_SERVER_FLAGS} -of=bin/dcd-server
