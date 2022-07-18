" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexMetaXML.vim
" Last Modified: 2012-06-19
" Author: Andrey Gavrikov 
" Maintainers: 
"
" apexMetaXML.vim - utility methods for generating *-meta.xml files when new
" Class/Page/Trigger is created
"
if exists("g:loaded_apex_metaXml") || &compatible
  finish
endif
let g:loaded_apex_metaXml = 1

"get script folder
"This has to be outside of a function or anything, otherwise it does not return
"proper path
let s:PLUGIN_FOLDER = expand("<sfile>:h")

let s:SUPPORTED_FILE_TYPES = ["ApexClass", "ApexPage", "ApexTrigger", "ApexComponent", "LightningComponentBundle"]

" request file type/name, check that file does not exist, create file and switch
" buffer to the new file
" param: filePath - full path of current apex file - needed to determine
" project location
function apexMetaXml#createFileAndSwitch(filePath)
	let projectSrcPath = apex#getApexProjectSrcPath(a:filePath)

	let typeAndName = s:fileTypeMenu(a:filePath)
	if len(typeAndName) < 1
		echo "\n"
		echomsg "Selection aborted"
        " user aborted
		return 
	endif
	let fileObjects = s:getFiles{typeAndName.fileType}(typeAndName.fileName)
    " fileObjects = {files :[name: 'helloWorld.html', content: '...', path: ['lwc', 'helloWorld']]}
    
    let filePathToEdit = ""

    for fileObject in fileObjects.files
        let l:folders = fileObject.path
        let folderPath = apexOs#joinPath([projectSrcPath] + l:folders)
        if !isdirectory(folderPath)
            call apexOs#createDir(folderPath)
        endif

        let newFilePath = apexOs#joinPath([folderPath, fileObject.name])
        if filereadable(newFilePath)
            echo "\n"
            call apexUtil#warning("File already exists: " . newFilePath)
            continue
        endif

        let writeRes = writefile(fileObject.content, newFilePath )
        if 0 == writeRes 
            if has_key(fileObject, "openForEditing") && 1 == fileObject.openForEditing
                let filePathToEdit = newFilePath
            endif	
        endif

    endfor

    if !empty(filePathToEdit)
        "switch to the buffer with newly created file
        silent exe "edit ".fnameescape(filePathToEdit)
    endif
    
endfun

" package.xml is a map which looks like this
" {
"	type-name1:[member1, member2, ...], 
"	type-name2:[*, member1, member2,...],
" ...}
function! apexMetaXml#packageXmlNew()
	return {}
endfunction	

"write definition of package.xml to be used with destructive delete
"
"package.xml used for Delete operation is very simple and does not have
"dynamic parts, looks like this:
"
"<?xml version="1.0" encoding="UTF-8"?>
"<Package xmlns="http://soap.sforce.com/2006/04/metadata">
"	<fullName>src</fullName>
"	<version>19.0</version>
"</Package>
"Args:
"srcFolderPath - path to folder where package.xml is to be created
"
function! apexMetaXml#packageWriteDestructive(srcFolderPath)
	let lines = s:getHeader()
	call add(lines, "<fullName>src</fullName>")
	"append footer
	call extend(lines, s:getFooter())

	let fname = apexOs#joinPath([a:srcFolderPath, "package.xml"])
	call writefile(lines, fname)
	return fname
endfunction	
"read existing package.xml into a 'package' map
"Args:
"@param: srcFolderPath - full path to ./src folder or /full/path/to/package.xml
"
"@see apexMetaXml#packageXmlNew()
"@return: 'package' map
function! apexMetaXml#packageXmlRead(path)
	"check if path we were given is full path to "package.xml"
	let fname = a:path
	if isdirectory(fname) 
		let fname = apexOs#joinPath([fname, "package.xml"])
	endif
	if !filereadable(fname)
		echoerr "File ".fname." is not readable."
	endif

	let result = {}
	let curType = ''
	let members = []
	for line in readfile(fname, '', 10000) " assuming metadata types file will never contain more than 10K lines
		"echo "line=".line
        if line =~? '^\s*<types>\s*$'
			"echo "start new type"
			let curType = ''
			let members = []
		elseif line =~? '^\s*</types>\s*$'
			"echo "end type, record type and members".curType
			if len(curType) > 0
				let result[curType] = members
			endif
		elseif line =~? '^\s*<name>\(\w*\|*\)</name>\s*$'
			"<name>CustomApplication</name>
			let curType = substitute(line, '^\(\s*<name>\)\(\w*\)\(</name>\s*\)$', '\2', '')
			"echo "curType=".curType
		elseif line =~? '^\s*<members>\(\w*\|*\)</members>\s*$'
							"        ^ - Starting at the beginning of the string 
							"        \s* - optional whitespace 
							"        \(\w*\|*\) word or single star character
							"        \s* - optional whitespace 
							"        $ - end of line
			let member = substitute(line, '^\(\s*<members>\)\(\w*\|*\)\(</members>\s*\)$', '\2', '')
							"remove everything except second group match, i.e.
							"leave only content between </members>...</members>

			"echo "member=".member
			call add(members, member)
		end
	endfor
	"echo result
	return result
endfunction

" add new members to package 
"Args:
"@param: package - Map: meta-type-name => [member....]
"@param: meta-type to add
"@param: members to add for given meta-type
"
" ex: call packageXmlAdd(package, 'CustomObject', ['Account', 'My_Object__c', '*'])
"Return:
"		>0 if changes were made to given package, otherwise 0
function! apexMetaXml#packageXmlAdd(package, type, members)
	let package = a:package
	let members = []
	if has_key(package, a:type)
		let members = package[a:type]
	endif

	let countChanges = 0
	" add all members making sure they are not already included
	for member in a:members
		if len(members) >0 && index(members, member) >= 0
			"already exist
			continue
		endif
		call add(members, member)
		let countChanges += 1
	endfor
	let package[a:type] = members
	return countChanges
endfunction	

" write well formed package.xml using 'package' map previously created with
" apexMetaXml#packageXmlNew and apexMetaXml#packageXmlAdd methods
"
"Args:
" package: - instance of package created by previous packageRead or packageAdd
" commands
" srcFolderPath: - full path to folder where fiel will be created
" param 3: [optional] package file name, if not provided then package.xml file name is
" used
"
"Return:
" return: /full/path/to/package.xml
function! apexMetaXml#packageWrite(package, srcFolderPath, ...)
	let package = a:package
	if len(package) < 1
		return ""
	endif
	"start with file header
	let lines = s:getHeader()

	let sortedKeys = sort(keys(package))

	for key in sortedKeys
		let members = package[key]
		call add(lines, "    <types>")
		for member in members
			call add(lines, "        <members>" . member . "</members>")
		endfor
		call add(lines, "        <name>" . key . "</name>")
		call add(lines, "    </types>")
	endfor

	"append footer
	call extend(lines, s:getFooter())

	let fileName = "package.xml"
	if a:0 > 0
		let fileName = a:1
	endif
	let fname = apexOs#joinPath([a:srcFolderPath, fileName])
	"echo "lines.size=".len(lines)
	if 0 == writefile(lines, fname)
		return fname
	endif
	return '' "failed to write package or nothing to write
endfunction

" build package.xml based on the existing ./src/ folder content
" package.xml is a map which looks like this
" {
"	type-name1:[member1, member2, ...], 
"	type-name2:[*, member1, member2,...],
" ...}
"Args:
"@param: srcFolderPath: full path to ./src folder which will be passed to ant
"@param: options - 
"		if contains 'p' then user will be prompted to add missing type to
"		package.xml, otherwise type will be added with a wildcard silently
"
"Return:
" return: /full/path/to/package.xml or "" if no changes made
function! apexMetaXml#packageXmlGenerate(projectRec, packageXmlPath, options)
	let package = apexMetaXml#packageXmlRead(a:packageXmlPath)
	let srcFolderPath = apex#getApexProjectSrcPath(a:packageXmlPath)

	"check each subfolder and make sure its metatype and components are
	"present in package.xml
	let files = apexOs#glob(srcFolderPath . "**/*")
	" visit each folder and check if it is part of package.xml
	let hasChanged = 0
	let showPrompt = (a:options =~# 'p')
	let metaTypes = apexRetrieve#getTypeXmlByFolder(a:projectRec, 0)
	for path in files
		if isdirectory(path)
			let folderName = apexOs#splitPath(path).tail
			let addMissing = 0

			if has_key(metaTypes, folderName) 
				let typeName = metaTypes[folderName]
				call s:showTypeWarning(typeName)

				if has_key(package, typeName)
					continue
				endif	
				let addMissing = 1
				
				if showPrompt
					let addMissing = 0
					let response = input('Type "'.typeName.'" is missing in your package.xml do you want to deploy it anyway [Y/n]? ')
					if 'n' != response && 'N' != response
						let addMissing = 1
					endif	
				endif	
				if 1 == addMissing
					let metaTypes = apexRetrieve#getTypeXmlByFolder(a:projectRec, 0)
					if has_key(metaTypes, folderName)
						let typeName = metaTypes[folderName]
						if apexMetaXml#packageXmlAdd(package, typeName, ['*'])
							let hasChanged = 1
						endif
					endif
				endif
			endif
		endif	
	endfor

	if hasChanged
		return apexMetaXml#packageWrite(package, srcFolderPath)
	endif
	return ""
endfunction

" some types require special treatment in order to deploy successfully
" e.g. API v27 - in order to deploy Country & State picklist changes one has
" to DISABLE "State and Country Picklists" feature, deploy, and then enable it
" back
function! s:showTypeWarning(typeName)
	if a:typeName ==? 'settings'
		call apexUtil#warning('If you are deploying "State and Country Picklists" changes then make sure that this function is DISABLED in SFDC UI (Setup->Data Management) before deployment and RE-ENABLED afterwards. Otherwise your picklist changes will not be reflected in SFDC.')
	endif
endfunction	

function! s:getHeader()
	let lines = ['<?xml version="1.0" encoding="UTF-8"?>',
				\ '<Package xmlns="http://soap.sforce.com/2006/04/metadata">',
				\]
	return lines
endfunction

function! s:getFooter()
	let lines = [ "    <version>".s:stringify(g:apex_API_version)."</version>",
				\ "</Package>",
				\]
	return lines
endfunction

" display menu with file types
" @return: {fileType: "Selected File Type", fileName: "User defined File name"}
"		ex: {fileType: "ApexClass", fileName: "MyControllerTest"}
"
function s:fileTypeMenu(filePath)
	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	if projectPath == ""
		echoerr "src folder not found using file path: ".a:filePath
		return ""
	endif
	let textList = ["Select file Type:"]
	let i = 1
	for ftype in s:SUPPORTED_FILE_TYPES
		let textList = textList + [i.". ".ftype]
		let i = i + 1
	endfor	
	let res = inputlist(textList)
	if res > 0 && res <= len(s:SUPPORTED_FILE_TYPES)
		let fType = s:SUPPORTED_FILE_TYPES[res-1]
		let fName = input("Please enter ".fType." name: ")
		if len(fName) < 1
			return {}
		endif	
		return {"fileType": fType, "fileName": fName}
	endif
	return {} " error or calcelled selection
endfun	


" generate 2 files
" <classname>.cls
" <classname>.cls-meta.xml
" @return: {
"       files :[ 
"           { name: 'HelloWorld.cls', content: '...', path: ['pages']} 
"           { name: 'HelloWorld.cls-meta.xml', content: '...', path: ['classes']} 
"       ]
"   }
"
function s:getFilesApexClass(fName)
    let fName = a:fName . ".cls"

	let fileContent = ["public inherited sharing class ". a:fName . " {", "}"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexClass xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". s:stringify(g:apex_API_version) . "</apiVersion>"]
	let metaContent = metaContent + ["    <status>Active</status>"]
	let metaContent = metaContent + ["</ApexClass>"]

    let l:files = []
    let l:files = l:files + [ {"name": fName, "content": fileContent, "path": ["classes"], "openForEditing": 1} ]
    let l:files = l:files + [ {"name": fName . "-meta.xml", "content": metaContent, "path": ["classes"] } ]

    return {"files": l:files}
endfun	

" generate 2 files
" <pagename>.page
" <pagename>.page-meta.xml
" @return: {
"       files :[ 
"           { name: 'HelloWorld.page', content: '...', path: ['pages']} 
"           { name: 'HelloWorld.page-meta.xml', content: '...', path: ['pages']} 
"       ]
"   }
"
function s:getFilesApexPage(fName)
    let fName = a:fName . ".page"

	let fileContent = ["<apex:page>", "</apex:page>"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexPage xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". s:stringify(g:apex_API_version) . "</apiVersion>"]
	let metaContent = metaContent + ["    <label>".a:fName."</label>"]
	let metaContent = metaContent + ["</ApexPage>"]

    let l:files = []
    let l:files = l:files + [ {"name": fName, "content": fileContent, "path": ["pages"], "openForEditing": 1} ]
    let l:files = l:files + [ {"name": fName . "-meta.xml", "content": metaContent, "path": ["pages"] } ]

    return {"files": l:files}

endfun	

" generate 2 files
" <triggername>.trigger
" <triggername>.trigger-meta.xml
" @return: {
"       files :[ 
"           { name: 'HelloWorld.trigger', content: '...', path: ['pages']} 
"           { name: 'HelloWorld.trigger-meta.xml', content: '...', path: ['triggers']} 
"       ]
"   }
function s:getFilesApexTrigger(fName)
    let fName = a:fName . ".trigger"

	let fileContent = ["trigger " . a:fName . " on <Object> (<events>) {", "}"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexTrigger xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". s:stringify(g:apex_API_version) . "</apiVersion>"]
	let metaContent = metaContent + ["    <status>Active</status>"]
	let metaContent = metaContent + ["</ApexTrigger>"]

    let l:files = []
    let l:files = l:files + [ {"name": fName, "content": fileContent, "path": ["triggers"], "openForEditing": 1} ]
    let l:files = l:files + [ {"name": fName . "-meta.xml", "content": metaContent, "path": ["triggers"] } ]

    return {"files": l:files}

endfun	

" generate 2 files
" <componentname>.component
" <componentname>.component-meta.xml
" @return: {
"       files :[ 
"           { name: 'HelloWorld.trigger', content: '...', path: ['pages']} 
"           { name: 'HelloWorld.trigger-meta.xml', content: '...', path: ['triggers']} 
"       ]
"   }
function s:getFilesApexComponent(fName)
    let fName = a:fName . ".component"
	let fileContent = ["<apex:component>", "</apex:component>"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexComponent xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". s:stringify(g:apex_API_version) . "</apiVersion>"]
	let metaContent = metaContent + ["    <label>".a:fName."</label>"]
	let metaContent = metaContent + ["</ApexComponent>"]

    let l:files = []
    let l:files = l:files + [ {"name": fName, "content": fileContent, "path": ["components"], "openForEditing": 1} ]
    let l:files = l:files + [ {"name": fName . "-meta.xml", "content": metaContent, "path": ["components"] } ]

    return {"files": l:files}

endfun	
"
" generate 3 files
" <componentname>.html
" <componentname>.js
" <componentname>.js-meta.xml
" @return: {files :[name: '', content: '', path: ['lwc', '']]}

function s:getFilesLightningComponentBundle(fName)
    let bundleName = tolower(a:fName[0]) . a:fName[1:]
    let fName = bundleName
    let className = toupper(a:fName[0]) . a:fName[1:]

	let htmlContent = ["<template>", "</template>"]
    let htmlFileName = fName . ".html"

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ['<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata" fqn="' .fName. '">']
	let metaContent = metaContent + ["  <apiVersion>". s:stringify(g:apex_API_version) . "</apiVersion>"]
	let metaContent = metaContent + ["  <isExposed>true</isExposed>"]
    let metaContent = metaContent + ["  <targets>"]
    let metaContent = metaContent + ["    <target>lightning__AppPage</target>"]
    let metaContent = metaContent + ["    <target>lightning__RecordPage</target>"]
    let metaContent = metaContent + ["    <target>lightning__HomePage</target>"]
    let metaContent = metaContent + ["    <target>lightning__Tab</target>"]
    let metaContent = metaContent + ["    <!-- <target>lightning__FlowScreen</target> -->"]
    let metaContent = metaContent + ["    <!-- <target>lightning__UtilityBar</target> -->"]
    let metaContent = metaContent + ["    <!-- <target>lightning__Inbox</target> -->"]
    let metaContent = metaContent + ["    <!-- <target>lightningCommunity__Page</target> -->"]
    let metaContent = metaContent + ["    <!-- <target>lightningCommunity__Default</target> -->"]
    let metaContent = metaContent + ["    <!-- <target>lightningSnapin__ChatMessage</target> -->"]
    let metaContent = metaContent + ["  </targets>"]
	let metaContent = metaContent + ["</LightningComponentBundle>"]
    let metaFileName = fName . ".js-meta.xml"

    let jsContent = []
    let jsContent = jsContent + ["import { LightningElement, track, api } from 'lwc';"]
    let jsContent = jsContent + ["export default class ". className ." extends LightningElement {"]
    let jsContent = jsContent + [""]
    let jsContent = jsContent + ["}"]
    let jsFileName = fName . ".js"

    let l:files = []
    let l:files = l:files + [ {"name": htmlFileName, "content": htmlContent, "path": ["lwc", bundleName], "openForEditing": 1} ]
    let l:files = l:files + [ {"name": metaFileName, "content": metaContent, "path": ["lwc", bundleName]} ]
    let l:files = l:files + [ {"name": jsFileName, "content": jsContent, "path": ["lwc", bundleName]} ]
    

	return {"files": l:files}

endfun	

" generate a string for the provided value without
" additional surrounding quotes that string creates
" @param: target value to be converted into a string
" @return: string representation of the provided value
"     without additional surrounding quotes
function s:stringify(value)
	if type(a:value) == type("")
		return a:value
	else
		return string(a:value)
	end
endfun
