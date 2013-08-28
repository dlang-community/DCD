setlocal omnifunc=dcomplete#Complete

command! -buffer DCDstartServer execute '!'.dcomplete#DCDserver().' > /dev/null &'
command! -buffer -nargs=? DCD execute '!'.dcomplete#DCDclient().' '.<q-args>
command! -buffer DCDstopServer DCD --shutdown
command! -buffer -nargs=1 -complete=dir DCDaddPath DCD -I<args>
