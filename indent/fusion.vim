" Vim indent file
" Language:  Neos.Fusion (incl. AFX)
" License:   MIT
"
" Block indentation based on `{`/`}` and AFX tags. Deliberately kept simple:
" Tree-sitter provides the more precise indentation through `indents.scm` (if
" installed); this file is the fallback.

if exists('b:did_indent')
  finish
endif
let b:did_indent = 1

setlocal indentexpr=GetFusionIndent()
setlocal indentkeys=0{,0},0),!^F,o,O,e,<>>
setlocal nolisp
setlocal nosmartindent

let b:undo_indent = 'setlocal indentexpr< indentkeys< lisp< smartindent<'

if exists('*GetFusionIndent')
  finish
endif

" The line without comments and without string contents, so that braces inside
" literals do not distort the indentation.
function! s:Strip(line) abort
  let l:line = a:line
  let l:line = substitute(l:line, "'[^']*'", "''", 'g')
  let l:line = substitute(l:line, '"[^"]*"', '""', 'g')
  let l:line = substitute(l:line, '`[^`]*`', '``', 'g')
  let l:line = substitute(l:line, '//.*$', '', '')
  let l:line = substitute(l:line, '/\*.\{-}\*/', '', 'g')
  let l:line = substitute(l:line, '^\s*#.*$', '', '')
  return l:line
endfunction

function! GetFusionIndent() abort
  let l:lnum = v:lnum
  let l:prev = prevnonblank(l:lnum - 1)
  if l:prev == 0
    return 0
  endif

  let l:prevline = s:Strip(getline(l:prev))
  let l:curline  = s:Strip(getline(l:lnum))
  let l:indent   = indent(l:prev)
  let l:sw       = shiftwidth()

  " Opening braces on the previous line increase, closing ones decrease.
  let l:open  = strlen(substitute(l:prevline, '[^{]', '', 'g'))
  let l:close = strlen(substitute(l:prevline, '[^}]', '', 'g'))
  let l:indent += (l:open - l:close) * l:sw

  " AFX: opening tag without self-closing and without a matching close tag
  if l:prevline =~# '<[A-Za-z_][A-Za-z0-9_.:-]*\%([^>]*\)\?>\s*$'
        \ && l:prevline !~# '/>\s*$'
        \ && l:prevline !~# '</[A-Za-z_][A-Za-z0-9_.:-]*>\s*$'
    let l:indent += l:sw
  endif
  " Multi-line tag: `<Tag` without `>` at the end of the line
  if l:prevline =~# '<[A-Za-z_][A-Za-z0-9_.:-]*[^>]*$'
    let l:indent += l:sw
  endif
  " Start of afx`
  if l:prevline =~# 'afx`\s*$'
    let l:indent += l:sw
  endif

  " The current line starts with a closing element -> outdent.
  if l:curline =~# '^\s*}'
    let l:indent -= l:sw
  endif
  if l:curline =~# '^\s*</'
    let l:indent -= l:sw
  endif
  if l:curline =~# '^\s*/>'
    let l:indent -= l:sw
  endif
  if l:curline =~# '^\s*`'
    let l:indent -= l:sw
  endif

  return l:indent < 0 ? 0 : l:indent
endfunction
