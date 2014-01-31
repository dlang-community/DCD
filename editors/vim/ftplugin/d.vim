setlocal omnifunc=dcomplete#Complete

if has('win32')
	command! -buffer -nargs=* -complete=dir DCDstartServer execute '!start '.dcomplete#DCDserver().' '.dcomplete#initImportPath().
				\ ' '.dcomplete#globImportPath([<f-args>])
else
	command! -buffer -nargs=* -complete=dir DCDstartServer execute '!'.dcomplete#DCDserver().' '.dcomplete#initImportPath().
				\ ' '.dcomplete#globImportPath([<f-args>]).' > /dev/null &'
endif
command! -buffer -nargs=? DCD execute '!'.dcomplete#DCDclient().' '.<q-args>
command! -buffer -nargs=? DCDonCurrentBufferPosition echo dcomplete#runDCDOnCurrentBufferPosition(<q-args>)
command! -buffer DCDstopServer DCD --shutdown
command! -buffer -nargs=+ -complete=dir DCDaddPath execute 'DCD '.dcomplete#globImportPath([<f-args>])
command! -buffer DCDclearCache DCD --clearCache

command! -buffer DCDdoc DCDonCurrentBufferPosition --doc
command! -buffer DCDsymbolLocation call dcomplete#runDCDtoJumpToSymbolLocation()
