"The completion function
function! dcomplete#Complete(findstart,base)
	if a:findstart
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
		if line('.')==prePos[0] && getline(prePos[0])[prePos[1]]=~'\w'
			return prePos[1]
		endif
		"If we can't find any of the above, DCD can't help us.
		return -2
	else
		"Run DCD
		let scanResult=s:runDCDToGetAutocompletion()
		"Split the result text to lines.
		let resultLines=split(scanResult,"\n")

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
		return dcomplete#globImportPath(g:dcd_importPath)
	endif
	return ''
endfunction

"Run DCD to get autocompletion results
function! s:runDCDToGetAutocompletion()

	let l:tmpFileName=tempname()
	"Save the temp file in unix format for better reading of byte position.
	let l:oldFileFormat=&fileformat
	set fileformat=unix
	let l:bytePosition=line2byte('.')+b:completionColumn-2
	exec "write ".l:tmpFileName
	let &fileformat=l:oldFileFormat
	let scanResult=system(dcomplete#DCDclient().' --cursorPos '.l:bytePosition.' <'.shellescape(l:tmpFileName))
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
			let funcArgsString=join(funcArgs,', ').')'
			call add(result,{'word':funcArgsString,'abbr':substitute(resultLine,'\\n\\t','','g'),'dup':1})
		end
	endfor
	return result
endfunction
