" Vim syntax file
" Language:     Neos.Fusion (incl. AFX)
" Maintainer:   neos-fusion.nvim
" License:      MIT
"
" Fallback syntax for the case that no Tree-sitter parser `fusion` is
" installed. Developed from scratch against the public Fusion language
" documentation; no third-party grammar material was copied.
"
" Deliberately conservative: all ambiguous constructs (strings, Eel, AFX) are
" regions. That keeps the top-level matches (comments, operators) from bleeding
" into strings or embedded languages.

if exists('b:current_syntax')
  finish
endif

" `syntax = false` disables the fallback syntax completely.
if luaeval("(function() local ok, c = pcall(require, 'neos_fusion.config'); return ok and c.get().syntax == false end)()")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syn case match
syn sync minlines=100 maxlines=500

" ------------------------------------------------------------------ Comments
syn keyword fusionTodo          contained TODO FIXME XXX NOTE HACK
syn region  fusionBlockComment  start=+/\*+ end=+\*/+ contains=fusionTodo,@Spell keepend
syn match   fusionLineComment   +//.*$+ contains=fusionTodo,@Spell
" `#` only starts a comment at the beginning of a statement. A `#` inside
" `${...}` or inside strings is shielded by the respective regions.
syn match   fusionHashComment   +^\s*#.*$+ contains=fusionTodo,@Spell

" ------------------------------------------------------------------- Values
syn match   fusionNumber        "\<-\=\d\+\%(\.\d\+\)\?\>"
syn keyword fusionBoolean       true false TRUE FALSE
syn keyword fusionNull          null NULL

syn region  fusionStringS       start=+'+ skip=+\\.+ end=+'+ contains=@Spell
syn region  fusionStringD       start=+"+ skip=+\\.+ end=+"+ contains=fusionEelInString,@Spell

" ---------------------------------------------------------------- Eel / AFX
" Eel expressions `${ ... }`. `matchgroup` keeps the delimiters separate so
" that nested `{}` are counted correctly.
syn region  fusionEel
      \ matchgroup=fusionEelDelimiter start=+\${+ end=+}+
      \ contains=fusionEelBraces,fusionEelString,fusionEelStringD,fusionEelNumber,fusionEelOperator,fusionEelHelper,fusionEelKeyword
      \ keepend extend
syn region  fusionEelBraces     contained matchgroup=fusionEelDelimiter start=+{+ end=+}+
      \ contains=fusionEelBraces,fusionEelString,fusionEelStringD,fusionEelNumber,fusionEelOperator,fusionEelHelper,fusionEelKeyword
syn region  fusionEelString     contained start=+'+ skip=+\\.+ end=+'+
syn region  fusionEelStringD    contained start=+"+ skip=+\\.+ end=+"+
syn match   fusionEelNumber     contained "\<-\=\d\+\%(\.\d\+\)\?\>"
syn match   fusionEelOperator   contained "[+\-*/%<>=!?:.|&]\|&&\|||"
syn keyword fusionEelKeyword    contained true false null this props site node documentNode request
" Eel helper calls such as `Array.first(...)` or `q(node).property(...)`
syn match   fusionEelHelper     contained "\<\u\w*\%(\.\w\+\)*\ze\s*("
syn match   fusionEelHelper     contained "\<q\ze("

" Eel inside double-quoted strings (interpolation is common there).
syn region  fusionEelInString   contained matchgroup=fusionEelDelimiter start=+\${+ end=+}+
      \ contains=fusionEelString,fusionEelNumber,fusionEelOperator,fusionEelHelper,fusionEelKeyword

" AFX: `afx\`` ... `\`` — JSX-like template language.
syn region  fusionAfx
      \ matchgroup=fusionAfxDelimiter start=+\<afx`+ end=+`+
      \ contains=fusionAfxTag,fusionAfxCloseTag,fusionAfxComment,fusionAfxExpr,fusionEel
      \ keepend extend

syn region  fusionAfxComment    contained start=+{/\*+ end=+\*/}+ contains=fusionTodo,@Spell
" `{ ... }` as an expression in the AFX body or in attributes
syn region  fusionAfxExpr       contained matchgroup=fusionAfxBrace start=+{+ end=+}+
      \ contains=fusionAfxExprInner,fusionEelString,fusionEelStringD,fusionEelNumber,fusionEelOperator,fusionEelHelper,fusionEelKeyword
syn region  fusionAfxExprInner  contained matchgroup=fusionAfxBrace start=+{+ end=+}+
      \ contains=fusionAfxExprInner,fusionEelString,fusionEelStringD,fusionEelNumber,fusionEelOperator,fusionEelHelper,fusionEelKeyword

syn region  fusionAfxTag        contained
      \ matchgroup=fusionAfxTagDelimiter start=+<\%(/\)\@!\%(\w\|\.\|:\)\@=+ end=+/\?>+
      \ contains=fusionAfxTagName,fusionAfxAttribute,fusionAfxAttrValue,fusionAfxExpr,fusionAfxSpread
      \ keepend
syn region  fusionAfxCloseTag   contained
      \ matchgroup=fusionAfxTagDelimiter start=+</+ end=+>+
      \ contains=fusionAfxTagName

syn match   fusionAfxTagName    contained "\%(<\|</\)\@<=[A-Za-z_][A-Za-z0-9_.:-]*"
syn match   fusionAfxAttribute  contained "\<[A-Za-z_@][A-Za-z0-9_.:-]*\ze\s*="
syn match   fusionAfxSpread     contained "{\.\.\."
syn region  fusionAfxAttrValue  contained start=+"+ skip=+\\.+ end=+"+ contains=fusionEelInString
syn region  fusionAfxAttrValue  contained start=+'+ skip=+\\.+ end=+'+

" ------------------------------------------------------------ Language frame
" `prototype(Vendor.Site:Component)`
syn region  fusionPrototypeCall
      \ matchgroup=fusionPrototypeKeyword start=+\<prototype(+ end=+)+
      \ contains=fusionPrototypeName oneline
syn match   fusionPrototypeName contained "[A-Za-z_][A-Za-z0-9_.]*\%(:[A-Za-z_][A-Za-z0-9_.]*\)\?"

" File-wide statements
syn match   fusionInclude       "^\s*include\s*:.*$" contains=fusionIncludeKeyword,fusionStringS,fusionStringD
syn keyword fusionIncludeKeyword contained include
syn match   fusionNamespace     "^\s*namespace\s*:.*$" contains=fusionNamespaceKeyword
syn keyword fusionNamespaceKeyword contained namespace

" Meta properties: @if, @process, @context, @position, @apply, @override, ...
syn match   fusionMetaProperty  "@[A-Za-z_][A-Za-z0-9_]*"

" Paths left of the operator, e.g. `page.body.content.main`
syn match   fusionPath          "^\s*\zs[A-Za-z_@][A-Za-z0-9_.:-]*\%(\s*\.\s*[A-Za-z_@][A-Za-z0-9_.:-]*\)*\ze\s*[<>=]"
      \ contains=fusionMetaProperty

" Operators: assignment, copy/inheritance, unset
syn match   fusionAssign        "="
syn match   fusionCopy          "<\%(\s*prototype\)\@="
syn match   fusionCopy          "^\s*[A-Za-z0-9_.@:-]\+\s*\zs<\ze\s"
syn match   fusionUnset         "^\s*[A-Za-z0-9_.@:-]\+\s*\zs>\ze\s*$"

syn match   fusionBrace         "[{}]"

" ---------------------------------------------------------- Highlight links
hi def link fusionTodo              Todo
hi def link fusionBlockComment      Comment
hi def link fusionLineComment       Comment
hi def link fusionHashComment       Comment
hi def link fusionNumber            Number
hi def link fusionBoolean           Boolean
hi def link fusionNull              Constant
hi def link fusionStringS           String
hi def link fusionStringD           String

hi def link fusionEel               Normal
hi def link fusionEelDelimiter      PreProc
hi def link fusionEelString         String
hi def link fusionEelStringD        String
hi def link fusionEelNumber         Number
hi def link fusionEelOperator       Operator
hi def link fusionEelKeyword        Keyword
hi def link fusionEelHelper         Function
hi def link fusionEelInString       Normal

hi def link fusionAfxDelimiter      PreProc
hi def link fusionAfxTagDelimiter   Delimiter
hi def link fusionAfxTagName        Tag
hi def link fusionAfxAttribute      Identifier
hi def link fusionAfxAttrValue      String
hi def link fusionAfxBrace          Delimiter
hi def link fusionAfxSpread         Delimiter
hi def link fusionAfxComment        Comment

hi def link fusionPrototypeKeyword  Statement
hi def link fusionPrototypeName     Type
hi def link fusionIncludeKeyword    Include
hi def link fusionInclude           Normal
hi def link fusionNamespaceKeyword  Include
hi def link fusionNamespace         Normal
hi def link fusionMetaProperty      Special
hi def link fusionPath              Identifier
hi def link fusionAssign            Operator
hi def link fusionCopy              Operator
hi def link fusionUnset             Operator
hi def link fusionBrace             Delimiter

let b:current_syntax = 'fusion'

let &cpo = s:cpo_save
unlet s:cpo_save
