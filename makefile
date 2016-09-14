.PHONY: all

all: dmd
dmd: dmdserver dmdclient
debug: dmdclient debugserver
gdc: gdcserver gdcclient
ldc: ldcserver ldcclient

DMD := dmd
GDC := gdc
LDC := ldc2

DPARSE_DIR := libdparse
DSYMBOL_DIR := dsymbol

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

CLIENT_SRC := \
	$(shell find src/common -name "*.d")\
	$(shell find src/client -name "*.d")\
	$(shell find msgpack-d/src/ -name "*.d")

DMD_CLIENT_FLAGS := -Imsgpack-d/src\
	-Imsgpack-d/src\
	-J.\
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

SERVER_SRC := \
	$(shell find src/common -name "*.d")\
	$(shell find src/server -name "*.d")\
	$(shell find ${DSYMBOL_DIR}/src -name "*.d")\
	${DPARSE_DIR}/src/dparse/ast.d\
	${DPARSE_DIR}/src/dparse/entities.d\
	${DPARSE_DIR}/src/dparse/lexer.d\
	${DPARSE_DIR}/src/dparse/parser.d\
	${DPARSE_DIR}/src/dparse/formatter.d\
	${DPARSE_DIR}/src/dparse/rollback_allocator.d\
	${DPARSE_DIR}/src/dparse/stack_buffer.d\
	${DPARSE_DIR}/src/std/experimental/lexer.d\
	containers/src/containers/dynamicarray.d\
	containers/src/containers/ttree.d\
	containers/src/containers/unrolledlist.d\
	containers/src/containers/openhashset.d\
	containers/src/containers/hashset.d\
	containers/src/containers/internal/hash.d\
	containers/src/containers/internal/node.d\
	containers/src/containers/internal/storage_type.d\
	containers/src/containers/internal/element_type.d\
	containers/src/containers/internal/backwards.d\
	containers/src/containers/slist.d\
	$(shell find msgpack-d/src/ -name "*.d")

DMD_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-J.\
	-wi\
	-O\
	-release\
	-inline\
	-ofbin/dcd-server

DEBUG_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-wi\
	-g\
	-ofbin/dcd-server\
	-J.

GDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-J.\
	-O3\
	-frelease\
	-obin/dcd-server

LDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-Isrc\
	-J=.\
	-O5\
	-release

dmdclient: githash
	mkdir -p bin
	${DMD} ${CLIENT_SRC} ${DMD_CLIENT_FLAGS}

dmdserver: githash
	mkdir -p bin
	${DMD} ${SERVER_SRC} ${DMD_SERVER_FLAGS}

debugserver: githash
	mkdir -p bin
	${DMD} ${SERVER_SRC} ${DEBUG_SERVER_FLAGS}

gdcclient: githash
	mkdir -p bin
	${GDC} ${CLIENT_SRC} ${GDC_CLIENT_FLAGS}

gdcserver: githash
	mkdir -p bin
	${GDC} ${SERVER_SRC} ${GDC_SERVER_FLAGS}

ldcclient: githash
	${LDC} ${CLIENT_SRC} ${LDC_CLIENT_FLAGS}

ldcserver: githash
	${LDC} $(LDC_SERVER_FLAGS) ${SERVER_SRC} -oq -of=bin/dcd-server

test: debugserver dmdclient
	cd tests && ./run_tests.sh
