"=============================================================================
" FILE: util.vim
" AUTHOR: Shougo Matsushita <Shougo.Matsu at gmail.com>
" License: MIT license
"=============================================================================

let s:is_windows = has('win32') || has('win64')

function! defx#util#print_error(string) abort
  echohl Error | echomsg '[defx] '
        \ . defx#util#string(a:string) | echohl None
endfunction
function! defx#util#print_warning(string) abort
  echohl WarningMsg | echomsg '[defx] '
        \ . defx#util#string(a:string) | echohl None
endfunction
function! defx#util#print_debug(string) abort
  echomsg '[defx] ' . defx#util#string(a:string)
endfunction

function! defx#util#convert2list(expr) abort
  return type(a:expr) ==# type([]) ? a:expr : [a:expr]
endfunction
function! defx#util#string(expr) abort
  return type(a:expr) ==# type('') ? a:expr : string(a:expr)
endfunction

function! defx#util#has_yarp() abort
  return !has('nvim') || get(g:, 'defx#enable_yarp', 0)
endfunction

function! defx#util#execute_path(command, path) abort
  let save_wildignore = &wildignore
  try
    execute a:command '`=s:expand(a:path)`'
    if &l:filetype ==# ''
      filetype detect
    endif
  catch /^Vim\%((\a\+)\)\=:E325/
    " Ignore swap file error
  catch
    call defx#util#print_error(v:throwpoint)
    call defx#util#print_error(v:exception)
  finally
    let &wildignore = save_wildignore
  endtry
endfunction
function! s:expand(path) abort
  return s:substitute_path_separator(
        \ (a:path =~# '^\~') ? fnamemodify(a:path, ':p') :
        \ (a:path =~# '^\$\h\w*') ? substitute(a:path,
        \             '^\$\h\w*', '\=eval(submatch(0))', '') :
        \ a:path)
endfunction
function! s:substitute_path_separator(path) abort
  return s:is_windows ? substitute(a:path, '\\', '/', 'g') : a:path
endfunction

function! defx#util#call_defx(command, args) abort
  let [paths, context] = defx#util#_parse_options_args(a:args)
  call defx#start(paths, context)
endfunction

function! defx#util#_parse_options_args(cmdline) abort
  return s:parse_options(a:cmdline)
endfunction
function! s:re_unquoted_match(match) abort
  " Don't match a:match if it is located in-between unescaped single or double
  " quotes
  return a:match . '\v\ze([^"' . "'" . '\\]*(\\.|"([^"\\]*\\.)*[^"\\]*"|'
        \ . "'" . '([^' . "'" . '\\]*\\.)*[^' . "'" . '\\]*' . "'" . '))*[^"'
        \ . "'" . ']*$'
endfunction
function! s:remove_quote_pairs(s) abort
  " remove leading/ending quote pairs
  let s = a:s
  if s[0] ==# '"' && s[len(s) - 1] ==# '"'
    let s = s[1: len(s) - 2]
  elseif s[0] ==# "'" && s[len(s) - 1] ==# "'"
    let s = s[1: len(s) - 2]
  else
    let s = substitute(a:s, '\\\(.\)', "\\1", 'g')
  endif
  return s
endfunction
function! s:parse_options(cmdline) abort
  let args = []
  let options = {}

  " Eval
  let cmdline = (a:cmdline =~# '\\\@<!`.*\\\@<!`') ?
        \ s:eval_cmdline(a:cmdline) : a:cmdline

  for s in split(cmdline, s:re_unquoted_match('\%(\\\@<!\s\)\+'))
    let arg = substitute(s, '\\\( \)', '\1', 'g')
    let arg_key = substitute(arg, '=\zs.*$', '', '')

    let name = substitute(tr(arg_key, '-', '_'), '=$', '', '')[1:]
    if name =~# '^no_'
      let name = name[3:]
      let value = v:false
    else
      let value = (arg_key =~# '=$') ?
            \ s:remove_quote_pairs(arg[len(arg_key) :]) : v:true
    endif

    if index(keys(defx#init#_user_options()), name) >= 0
      let options[name] = value
    else
      call add(args, arg)
    endif
  endfor

  return [args, options]
endfunction
function! s:eval_cmdline(cmdline) abort
  let cmdline = ''
  let prev_match = 0
  let eval_pos = match(a:cmdline, '\\\@<!`.\{-}\\\@<!`')
  while eval_pos >= 0
    if eval_pos - prev_match > 0
      let cmdline .= a:cmdline[prev_match : eval_pos - 1]
    endif
    let prev_match = matchend(a:cmdline,
          \ '\\\@<!`.\{-}\\\@<!`', eval_pos)
    let cmdline .= escape(eval(a:cmdline[eval_pos+1 : prev_match - 2]), '\ ')

    let eval_pos = match(a:cmdline, '\\\@<!`.\{-}\\\@<!`', prev_match)
  endwhile
  if prev_match >= 0
    let cmdline .= a:cmdline[prev_match :]
  endif

  return cmdline
endfunction

function! defx#util#complete(arglead, cmdline, cursorpos) abort
  let _ = []

  if a:arglead =~# '^-'
    " Option names completion.
    let bool_options = keys(filter(copy(defx#init#_user_options()),
          \ 'type(v:val) == type(v:true) || type(v:val) == type(v:false)'))
    let _ += map(copy(bool_options), "'-' . tr(v:val, '_', '-')")
    let string_options = keys(filter(copy(defx#init#_user_options()),
          \ 'type(v:val) != type(v:true) && type(v:val) != type(v:false)'))
    let _ += map(copy(string_options), "'-' . tr(v:val, '_', '-') . '='")

    " Add "-no-" option names completion.
    let _ += map(copy(bool_options), "'-no-' . tr(v:val, '_', '-')")
  else
    " Path names completion.
    let files = filter(glob(a:arglead . '*', v:true, v:true),
          \ 'stridx(tolower(v:val), tolower(a:arglead)) == 0')
    let files = filter(files, 'isdirectory(v:val)')
    if a:arglead =~# '^\~'
      let home_pattern = '^'.
            \ s:substitute_path_separator(expand('~')).'/'
      call map(files, "substitute(v:val, home_pattern, '~/', '')")
    endif
    call map(files, "escape(v:val.'/', ' \\')")
    let _ += files
  endif

  return uniq(sort(filter(_, 'stridx(v:val, a:arglead) == 0')))
endfunction

function! defx#util#has_yarp() abort
  return !has('nvim')
endfunction
function! defx#util#rpcrequest(event, args) abort
  if !defx#init#_check_channel()
    return ''
  endif

  if defx#util#has_yarp()
    if g:defx#_yarp.job_is_dead
      return
    endif
    return g:defx#_yarp.request(a:event, a:args)
  else
    return call(a:event, a:args)
  endif
endfunction
