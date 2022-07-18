" File: apexLogActions.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Maintainers: 
" Last Modified: 2015-06-07
"
" apexLogActions.vim - logic related to handling Apex Logs
"
if exists("g:loaded_apexLogActions") || &compatible
      finish
endif
let g:loaded_apexLogActions = 1

let s:META_LOG_LEVEL = 'None'

let s:TRACE_FLAG = {"ApexCode": "Debug", "ApexProfiling": "Error", "Callout": "Error", "Database": "Error",
                    \ "System": "Error", "Validation": "Error", "Visualforce": "Error", "Workflow": "Error"}

let s:traceFlagLogTypeByLetter = {
            \ "1": "ApexCode",
            \ "2": "ApexProfiling",
            \ "3": "Callout",
            \ "4": "Database",
            \ "5": "System",
            \ "6": "Validation",
            \ "7": "Visualforce",
            \ "8": "Workflow"}

let s:DEBUGGING_HEADER = {"Apex_code": "Debug", "Apex_profiling": "Error", "Callout": "Error", "Db": "Error",
                    \ "System": "Error", "Validation": "Error", "Visualforce": "Error", "Workflow": "Error", "All": "Error"}

let s:debugingHeaderLogTypeByLetter = {
            \ "1": "Apex_code",
            \ "2": "Apex_profiling",
            \ "3": "Callout",
            \ "4": "Db",
            \ "5": "System",
            \ "6": "Validation",
            \ "7": "Visualforce",
            \ "8": "Workflow",
            \ "9": "All"}

function! apexLogActions#changeLogLevels(filePath)
    let l:userScope = "Trace Settings for User"
    let l:scope = apexUtil#menu("Select Scope", [l:userScope, "Class and Trigger Trace Overrides"], l:userScope)
    if l:userScope == l:scope
        call s:changeLogLevels(a:filePath, "user", "")
    else
        call s:changeClassOrTriggerLogLevels(a:filePath)
    endif
endfunction

function! s:changeClassOrTriggerLogLevels(filePath)
endfunction

function! apexLogActions#askLogLevel(filePath, api)
    if "meta" == a:api
        let g:apex_test_debuggingHeader = s:askDebuggingHeaderLogLevels()
    else " tooling api    
        let g:apex_test_traceFlag = s:askToolingLogLevels(a:filePath, "user", "")
    endif
    " simulate <CR> press to skip: 'Press ENTER or type command to continue'
    call feedkeys("\<CR>") 
endfunction

"Param2: project file path - which resides inside a project. Used to determine
"project name
"Param2: (optional) destination project name, must match one of .properties file
function! apexLogActions#deleteLogs(filePath, ...)
    let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	if a:0 > 0 && len(a:1) > 0
		let projectName = apexUtil#unescapeFileName(a:1)
	endif
    let l:extraParams = {}
    let l:projectObj = {"name": projectName}
	let resMap = apexToolingAsync#executeBlocking("deleteLogs", l:projectObj, l:extraParams, [])
	let responsePath = resMap["responseFilePath"]
endfunction    

" function! s:askMetaLogLevels()
"     if exists('g:apex_test_logType')
"         let s:META_LOG_LEVEL = g:apex_test_logType
"     endif
"     return apexUtil#menu('Select Log Type', ['None', 'Debugonly', 'Db', 'Profiling', 'Callout', 'Detail'], s:META_LOG_LEVEL)
" endfunction

function! s:askDebuggingHeaderLogLevels()
    if exists('g:apex_test_debuggingHeader') 
                \ && type({}) == type(g:apex_test_debuggingHeader) 
                \ && !empty(g:apex_test_debuggingHeader)
        
        let s:DEBUGGING_HEADER = g:apex_test_debuggingHeader
    endif
    let l:default = "Apply current values"
    let l:logTypeLetter = s:selectLogTypeToChange(l:default, s:DEBUGGING_HEADER, s:debugingHeaderLogTypeByLetter)

    while l:default != l:logTypeLetter
        let l:logType = s:debugingHeaderLogTypeByLetter[l:logTypeLetter]
        echo "\n"
        let l:logLevel = apexUtil#menu("Select Log Level for " . l:logType, ["Finest", "Finer", "Fine", "Debug", "Info", "Warn", "Error"], s:DEBUGGING_HEADER[l:logType])
        if !empty(l:logLevel)
            let s:DEBUGGING_HEADER[l:logType] = l:logLevel
        endif
        " confirm current values or move to next log type
        let l:logTypeLetter = s:selectLogTypeToChange(l:default, s:DEBUGGING_HEADER, s:debugingHeaderLogTypeByLetter)
    endwhile
    "return s:DEBUGGING_HEADER
    let l:jsonStr = substitute(string(s:DEBUGGING_HEADER), "'", '"', 'g')
    return l:jsonStr
endfunction


function! s:askToolingLogLevels(filePath, scope, tracedEntity)
    if exists('g:apex_test_traceFlag') 
                \ && type({}) == type(g:apex_test_traceFlag) 
                \ && !empty(g:apex_test_traceFlag)
        
        let s:TRACE_FLAG = g:apex_test_traceFlag
    endif
    let l:default = "Apply current values"
    let l:logTypeLetter = s:selectLogTypeToChange(l:default, s:TRACE_FLAG, s:traceFlagLogTypeByLetter)

    while l:default != l:logTypeLetter
        let l:logType = s:traceFlagLogTypeByLetter[l:logTypeLetter]
        echo "\n"
        let l:logLevel = apexUtil#menu("Select Log Level for " . l:logType, ["Finest", "Finer", "Fine", "Debug", "Info", "Warn", "Error"], s:TRACE_FLAG[l:logType])
        if !empty(l:logLevel)
            let s:TRACE_FLAG[l:logType] = l:logLevel
        endif
        " confirm current values or move to next log type
        let l:logTypeLetter = s:selectLogTypeToChange(l:default, s:TRACE_FLAG, s:traceFlagLogTypeByLetter)
    endwhile
    "return s:TRACE_FLAG
    let l:jsonStr = substitute(string(s:TRACE_FLAG), "'", '"', 'g')
    return l:jsonStr
endfunction

function! s:selectLogTypeToChange(default, valueSourceMap, valueByLetter)
    let l:logMenuItems = []
    for key in sort(keys(a:valueByLetter))
        let l:value = a:valueByLetter[key]
        let l:item = [key, l:value . " (" . a:valueSourceMap[l:value] . ")"]
        call add(l:logMenuItems, l:item)
    endfor
	
    return apexUtil#menu('Select Log Type to change', l:logMenuItems,  a:default)
endfunction

" call this to set new log/trace levels (this is not for unit test Trace Flag)
function! s:changeLogLevels(filePath, scope, tracedEntity)
    let l:jsonStr = s:askToolingLogLevels(a:filePath, a:scope, a:tracedEntity)
    call s:sendCommand(a:filePath, a:scope, a:tracedEntity, l:jsonStr)
endfunction

"Args:
"Param1: filePath - path to apex file in current project
function! s:sendCommand(filePath, scope, tracedEntity, traceFlagJson)
	let tempConfigFilePath = apexLogActions#saveTempTraceFlagConfig(a:traceFlagJson)
    
	let l:extraParams = {"traceFlagConfig": apexOs#shellescape(tempConfigFilePath)}
    if !empty(a:scope)
        let l:extraParams["scope"] = a:scope
    endif
    if !empty(a:tracedEntity)
        let l:extraParams["tracedEntity"] = a:tracedEntity
    endif
    
    let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
    let l:projectObj = {"path": projectPair.path, "name": projectPair.name, "packageName": "unpackaged"}
	let resMap = apexToolingAsync#executeBlocking("changeLogLevels", l:projectObj, l:extraParams, [])
	let responsePath = resMap["responseFilePath"]
endfunction

"Args:
"Param1: traceFlagJson - json string
function! apexLogActions#saveTempTraceFlagConfig(traceFlagJson)
	let tempFilePath = tempname() . "-apexTraceFlag.conf"

    let l:jsonStr = a:traceFlagJson
    if type({}) == type(a:traceFlagJson)
        let l:jsonStr = json_encode(a:traceFlagJson)
    endif    
    call writefile([l:jsonStr], tempFilePath)
    return tempFilePath
endfunction
