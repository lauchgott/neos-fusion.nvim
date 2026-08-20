" Vim indent file
" Language:  Neos.Fusion (inkl. AFX)
" License:   MIT
"
" Blockeinrueckung anhand von `{`/`}` sowie AFX-Tags. Bewusst einfach
" gehalten: Tree-sitter liefert (falls installiert) die genauere Einrueckung
" ueber `indents.scm`; diese Datei ist der Fallback.

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

" Zeile ohne Kommentare und ohne Stringinhalte, damit Klammern in Literalen
" die Einrueckung nicht verfaelschen.
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

  " Oeffnende Klammern in der Vorzeile erhoehen, schliessende senken.
  let l:open  = strlen(substitute(l:prevline, '[^{]', '', 'g'))
  let l:close = strlen(substitute(l:prevline, '[^}]', '', 'g'))
  let l:indent += (l:open - l:close) * l:sw

  " AFX: oeffnendes Tag ohne Selbstschluss und ohne passendes Schlusstag
  if l:prevline =~# '<[A-Za-z_][A-Za-z0-9_.:-]*\%([^>]*\)\?>\s*$'
        \ && l:prevline !~# '/>\s*$'
        \ && l:prevline !~# '</[A-Za-z_][A-Za-z0-9_.:-]*>\s*$'
    let l:indent += l:sw
  endif
  " Mehrzeiliges Tag: `<Tag` ohne `>` am Zeilenende
  if l:prevline =~# '<[A-Za-z_][A-Za-z0-9_.:-]*[^>]*$'
    let l:indent += l:sw
  endif
  " afx`-Beginn
  if l:prevline =~# 'afx`\s*$'
    let l:indent += l:sw
  endif

  " Aktuelle Zeile beginnt mit einem schliessenden Element -> ausruecken.
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
