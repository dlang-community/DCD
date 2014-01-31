"The completion function
function! dcomplete#Complete(findstart,base)
	if a:findstart
		"Vim temporarily deletes the current identifier from the file
		let b:currentLineText=getline('.')

		"We might need it for paren completion:
		let b:closingParenExists=getline('.')[col('.')-1:-1]=~'^\s*)'

		let prePos=searchpos('\W',"bn")
		let preChar=getline(prePos[0])[prePos[1]-1]
		if '.'==preChar
			let b:completionColumn=prePos[1]+1
			return prePos[1]
		endif
		"If we can't find a dot, we look for a paren.
		let parenPos=searchpos("(","bn",line('.'))
		if parenPos[0]
			if getline('.')[parenPos[1]:col('.')-2]=~'^\s*\w*$'
				let b:completionColumn=parenPos[1]+1
				return parenPos[1]
			endif
		endif
		"If we can't find either, look for the beginning of the word
		"if line('.')==prePos[0] && getline(prePos[0])[prePos[1]]=~'\w'
			"return prePos[1]
		"endif
		"If we can't find any of the above - just look for the begining of
		"the identifier
		let wordStartPos=searchpos('\w\+',"bn")
		if line('.')==wordStartPos[0]
			let b:completionColumn=wordStartPos[1]+2
			return wordStartPos[1]-1
		endif

		return -2
	else
		let b:base=a:base
		"Run DCD
		let l:prevCurrentLineText=getline('.')
		call setline('.',b:currentLineText)
		let scanResult=s:runDCDToGetAutocompletion()
		call setline('.',l:prevCurrentLineText)
		"Split the result text to lines.
		let resultLines=split(scanResult,"\n")
		let b:res=resultLines

		"if we have less than one line - something wen wrong
		if empty(resultLines)
			return 'bad...'
		endif
		"identify completion type via the first line.
		if resultLines[0]=='identifiers'
			return s:parsePairs(a:base,resultLines[1:],'','')
		elseif resultLines[0]=='calltips'
			return s:parseCalltips(a:base,resultLines[1:])
		endif
		return []
	endif
endfunction

"Get the DCD server command path
function! dcomplete#DCDserver()
	if exists('g:dcd_path')
		return shellescape(g:dcd_path.(has('win32') ? '\' : '/').'dcd-server')
	else
		return 'dcd-server'
	end
endfunction

"Get the DCD client command path
function! dcomplete#DCDclient()
	if exists('g:dcd_path')
		return shellescape(g:dcd_path.(has('win32') ? '\' : '/').'dcd-client')
	else
		return 'dcd-client'
	end
endfunction

"Use Vim's globbing on a path pattern or a list of patterns and translate them
"to DCD's syntax.
function! dcomplete#globImportPath(pattern)
	if(type(a:pattern)==type([]))
		return join(map(a:pattern,'dcomplete#globImportPath(v:val)'),' ')
	else
		return join(map(glob(a:pattern,0,1),'"-I".shellescape(v:val)'),' ')
	endif
endfunction

"Get the default import path when starting a server and translate them to
"DCD's syntax.
function! dcomplete#initImportPath()
	if exists('g:dcd_importPath')
		return dcomplete#globImportPath(copy(g:dcd_importPath))
	else
		return ''
	endif
endfunction

"Run DCD to get autocompletion results
function! s:runDCDToGetAutocompletion()
	return s:runDCDOnBufferBytePosition(line2byte('.')+b:completionColumn-2,'')
endfunction

"Run DCD on the current position in the buffer
function! dcomplete#runDCDOnCurrentBufferPosition(args)
	return s:runDCDOnBufferBytePosition(line2byte('.')+col('.')-1,a:args)
endfunction

"Find where the symbol under the cursor is declared and jump there
function! dcomplete#runDCDtoJumpToSymbolLocation()
	let l:scanResult=split(s:runDCDOnBufferBytePosition(line2byte('.')+col('.')-1,'--symbolLocation'),"\n")[0]
	let l:resultParts=split(l:scanResult,"\t")
	if 2!=len(l:resultParts)
		echo 'Not found!'
		return
	endif

	if l:resultParts[0]!='stdin'
		execute 'edit '.l:resultParts[0]
	endif

	let l:symbolByteLocation=str2nr(l:resultParts[1])
	if l:symbolByteLocation<1
		echo 'Not found!'
		return
	endif

	execute 'goto '.(l:symbolByteLocation+1)
endfunction

"Run DCD on the current buffer with the supplied position
function! s:runDCDOnBufferBytePosition(bytePosition,args)
	let l:tmpFileName=tempname()
	"Save the temp file in unix format for better reading of byte position.
	let l:oldFileFormat=&fileformat
	set fileformat=unix
	silent exec "write ".l:tmpFileName
	let &fileformat=l:oldFileFormat
	let scanResult=system(dcomplete#DCDclient().' '.a:args.' --cursorPos='.a:bytePosition.' <'.shellescape(l:tmpFileName))
	if v:shell_error
		throw scanResult
	endif
	call delete(l:tmpFileName)
	return scanResult
endfunction

"Parse simple pair results
function! s:parsePairs(base,resultLines,addBefore,addAfter)
	let result=[]
	for resultLine in a:resultLines
		if len(resultLine)
			let lineParts=split(resultLine)
			if lineParts[0]=~'^'.a:base && 2==len(lineParts) && 1==len(lineParts[1])
				call add(result,{'word':a:addBefore.lineParts[0].a:addAfter,'kind':lineParts[1]})
			endif
		end
	endfor
	return result
endfunction

"Parse function calltips results
function! s:parseCalltips(base,resultLines)
	let result=[a:base]
	for resultLine in a:resultLines
		if 0<=match(resultLine,".*(.*)")
			let funcArgs=[]
			for funcArg in split(resultLine[match(resultLine,'(')+1:-2],', ')
				let argParts=split(funcArg)
				if 1<len(argParts)
					call add(funcArgs,argParts[-1])
				else
					call add(funcArgs,'')
				endif
			endfor
			let funcArgsString=join(funcArgs,', ')
			if !b:closingParenExists && !(exists('g:dcd_neverAddClosingParen') && g:dcd_neverAddClosingParen)
				let funcArgsString=funcArgsString.')'
			endif
			call add(result,{'word':funcArgsString,'abbr':substitute(resultLine,'\\n\\t','','g'),'dup':1})
		end
	endfor
	return result
endfunction
