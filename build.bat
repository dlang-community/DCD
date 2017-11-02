IF "%DC%"=="" SET DC="dmd"

set containers_modules=
for /r "containers/src" %%F in (*.d) do call set containers_modules=%%containers_modules%% "%%F"

set common_modules=
for /r "src/dcd/common" %%F in (*.d) do call set common_modules=%%common_modules%% "%%F"

set server_modules=
for /r "src/dcd/server" %%F in (*.d) do call set server_modules=%%server_modules%% "%%F"

set dsymbol_modules=
for /r "dsymbol/src" %%F in (*.d) do call set dsymbol_modules=%%dsymbol_modules%% "%%F"

set libdparse_modules=
for /r "libdparse/src" %%F in (*.d) do call set libdparse_modules=%%libdparse_modules%% "%%F"

set msgspack_modules=
for /r "msgpack-d/src" %%F in (*.d) do call set msgspack_modules=%%msgspack_modules%% "%%F"

set client_name=bin\dcd-client
set server_name=bin\dcd-server

%DC%^
 src\dcd\client\client.d^
 src\dcd\common\messages.d^
 src\dcd\common\dcd_version.d^
 src\dcd\common\socket.d^
 %msgspack_modules%^
 -Imsgpack-d\src^
 -release -inline -O -wi^
 -of%client_name%

%DC%^
 %server_modules%^
 %dsymbol_modules%^
 %libdparse_modules%^
 %common_modules%^
 %containers_modules%^
 %msgspack_modules%^
 -Icontainers/src^
 -Imsgpack-d/src^
 -Ilibdparse/src^
 -wi -O -release^
 -of%server_name%

if exist %server_name%.obj del %server_name%.obj
if exist %client_name%.obj del %client_name%.obj
