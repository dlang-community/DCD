setlocal omnifunc=dcomplete#Complete

if has('win32')
	command! -buffer DCDstartServer execute '!start '.dcomplete#DCDserver().' '.dcomplete#initImportPath()
else
	command! -buffer DCDstartServer execute '!'.dcomplete#DCDserver().' '.dcomplete#initImportPath().' > /dev/null &'
endif
command! -buffer -nargs=? DCD execute '!'.dcomplete#DCDclient().' '.<q-args>
command! -buffer DCDstopServer DCD --shutdown
command! -buffer -nargs=+ -complete=dir DCDaddPath execute 'DCD '.dcomplete#globImportPath([<f-args>])
