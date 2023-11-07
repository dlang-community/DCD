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

SHELL:=/usr/bin/env bash

githash:
	@mkdir -p bin
	git describe --tags > bin/githash.txt

report:
	dscanner --report src > dscanner-report.json
	sonar-runner

clean:
	rm -rf bin
	rm -f dscanner-report.json
	rm -f githash.txt
	rm -f *.o

CLIENT_SRC := \
	$(shell find common/src/dcd/common -name "*.d")\
	$(shell find src/dcd/client -name "*.d")\
	$(shell find msgpack-d/src/ -name "*.d")

DMD_CLIENT_FLAGS := -Imsgpack-d/src\
	-Imsgpack-d/src\
	-Jbin\
	-inline\
	-O\
	-wi\
	-ofbin/dcd-client

GDC_CLIENT_FLAGS := -Imsgpack-d/src\
	-Jbin\
	-O3\
	-frelease\
	-obin/dcd-client

LDC_CLIENT_FLAGS := -Imsgpack-d/src\
	-Imsgpack-d/src\
	-J=bin\
	-release\
	-O5\
	-oq\
	-of=bin/dcd-client

override DMD_CLIENT_FLAGS += $(DFLAGS)
override LDC_CLIENT_FLAGS += $(DFLAGS)
override GDC_CLIENT_FLAGS += $(DFLAGS)

SERVER_SRC := \
	$(shell find common/src/dcd/common -name "*.d")\
	$(shell find src/dcd/server -name "*.d")\
	$(shell find ${DSYMBOL_DIR}/src -name "*.d")\
	$(shell find ${DPARSE_DIR}/src -name "*.d")\
	$(shell find containers/src -name "*.d")\
	$(shell find msgpack-d/src/ -name "*.d")

DMD_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-Jbin\
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
	-Jbin

GDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-Jbin\
	-O3\
	-frelease\
	-obin/dcd-server

LDC_SERVER_FLAGS := -Icontainers/src\
	-Imsgpack-d/src\
	-I${DPARSE_DIR}/src\
	-I${DSYMBOL_DIR}/src\
	-Isrc\
	-J=bin\
	-O5\
	-release

override DMD_SERVER_FLAGS += $(DFLAGS)
override LDC_SERVER_FLAGS += $(DFLAGS)
override GDC_SERVER_FLAGS += $(DFLAGS)

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
	${LDC} ${CLIENT_SRC} ${LDC_CLIENT_FLAGS} -oq -of=bin/dcd-client

ldcserver: githash
	${LDC} $(LDC_SERVER_FLAGS) ${SERVER_SRC} -oq -of=bin/dcd-server

test: debugserver dmdclient
	cd tests && ./run_tests.sh --extra

release:
	./release.sh
