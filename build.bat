IF "%DC%"=="" SET DC="dmd"
IF "%DC%"=="ldc2" SET DC="ldmd2"
IF "%DC%"=="gdc" SET DC="gdmd"
IF "%MFLAGS%"=="" SET MFLAGS="-m32"

:: git might not be installed, so we provide 0.0.0 as a fallback or use
:: the existing githash file if existent
if not exist "bin" mkdir bin
git describe --tags > bin\githash_.txt
for /f %%i in ("bin\githash_.txt") do set githashsize=%%~zi
if %githashsize% == 0 (
	if not exist "bin\githash.txt" (
		echo v0.0.0 > bin\githash.txt
	)
) else (
	move /y bin\githash_.txt bin\githash.txt
)

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

set stdx_allocator=
for /r "stdx-allocator/source/stdx/allocator" %%F in (*.d) do call set stdx_allocator=%%stdx_allocator%% "%%F"

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
 %MFLAGS%^
 -of%client_name%^
 -Jbin

%DC%^
 %server_modules%^
 %dsymbol_modules%^
 %libdparse_modules%^
 %common_modules%^
 %containers_modules%^
 %msgspack_modules%^
 %stdx_allocator%^
 -Icontainers/src^
 -Imsgpack-d/src^
 -Ilibdparse/src^
 -Istdx-allocator/source^
 -wi -O -release^
 -Jbin^
 %MFLAGS%^
 -of%server_name%

if exist %server_name%.obj del %server_name%.obj
if exist %client_name%.obj del %client_name%.obj
