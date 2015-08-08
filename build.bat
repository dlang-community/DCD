set containers_modules=
for /r "containers/src" %%F in (*.d) do call set containers_modules=%%containers_modules%% "%%F"

set common_modules=
for /r "src/common" %%F in (*.d) do call set common_modules=%%common_modules%% "%%F"

set server_modules=
for /r "src/server" %%F in (*.d) do call set server_modules=%%server_modules%% "%%F"

set dsymbol_modules=
for /r "dsymbol/src" %%F in (*.d) do call set dsymbol_modules=%%dsymbol_modules%% "%%F"

set libdparse_modules=
for /r "libdparse/src" %%F in (*.d) do call set libdparse_modules=%%libdparse_modules%% "%%F"

set client_name=bin\dcd_client
set server_name=bin\dcd_server

dmd^
 src\client\client.d^
 src\common\messages.d^
 src\common\dcd_version.d^
 msgpack-d\src\msgpack.d^
 -Imsgpack-d\src^
 -release -inline -O -wi^
 -of%client_name%

dmd^
 %server_modules%^
 %dsymbol_modules%^
 %libdparse_modules%^
 %common_modules%^
 %containers_modules%^
 msgpack-d/src/msgpack.d^
 -Icontainers/src^
 -Imsgpack-d/src^
 -Ilibdparse/src^
 -wi -O -release^
 -of%server_name%
 
if exist %server_name%.obj del %server_name%.obj
if exist %client_name%.obj del %client_name%.obj
