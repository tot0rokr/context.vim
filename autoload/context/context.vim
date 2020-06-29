let s:nil_line = context#line#make(0, 0, '')

" collect all context lines
function! context#context#get(base_line) abort
    let base_line = a:base_line
    if base_line.number == 0
        return []
    endif

    let context = {}

    if !exists('b:context') || b:context.tick != b:changedtick
        " skips is a dictionary that maps a line to its next context line so
        " it allows us to skip large portions of the buffer instead of always
        " having to scan through all of it
        let b:context = {
                    \ 'tick':  b:changedtick,
                    \ 'skips': {},
                    \ }
    endif

    while 1
        let context_line = s:get_context_line(base_line)
        let b:context.skips[base_line.number] = context_line.number " cache this lookup

        if context_line.number == 0
            break
        endif

        let indent = context_line.indent
        if !has_key(context, indent)
            let context[indent] = []
        endif

        call insert(context[indent], context_line, 0)

        " for next iteration
        let base_line = context_line
    endwhile

    " join, limit and get context lines
    " NOTE: at this stage lines changes from list to list of lists
    let lines = []
    for indent in sort(keys(context), 'N')
        " NOTE: s:join switches from list to list of lists, grouping lines
        " that are allowed to be joined on the caller side
        let context[indent] = s:join(context[indent])
        " TODO: do we need to apply this limit much later? or ignore?
        " TODO: implement limit somewhere else
        " NOTE: this used to limit per indent, add again?
        " let context[indent] = s:limit(context[indent], indent)
        call extend(lines, context[indent])
    endfor

    return lines
endfunction

function! s:get_context_line(line) abort
    " check if we have a skip available from the base line
    let skipped = get(b:context.skips, a:line.number, -1)
    if skipped != -1
        " call context#util#echof('  skipped', a:line.number, '->', skipped)
        return context#line#make(skipped, g:context.Indent(skipped), getline(skipped))
    endif

    " if line starts with closing brace or similar: jump to matching
    " opening one and add it to context. also for other prefixes to show
    " the if which belongs to an else etc.
    if context#line#should_extend(a:line.text)
        let max_indent = a:line.indent " allow same indent
    else
        let max_indent = a:line.indent - 1 " must be strictly less
    endif

    if max_indent < 0
        return s:nil_line
    endif

    " search for line with matching indent
    let current_line = a:line.number - 1
    while 1
        if current_line <= 0
            " nothing found
            return s:nil_line
        endif

        let indent = g:context.Indent(current_line)
        if indent > max_indent
            " use skip if we have, next line otherwise
            let skipped = get(b:context.skips, current_line, current_line-1)
            let current_line = skipped
            continue
        endif

        let line = getline(current_line)
        if context#line#should_skip(line)
            let current_line -= 1
            continue
        endif

        return context#line#make(current_line, indent, line)
    endwhile
endfunction

function! s:join(lines) abort
    if g:context.max_join_parts < 1
        " TODO: test this
        return a:lines
    endif

    " call context#util#echof('> join', len(a:lines))
    let pending = [] " lines which might be joined with previous
    let joined = a:lines[:0] " start with first line
    for line in a:lines[1:]
        if context#line#should_join(line.text)
            " add lines without word characters to pending list
            call add(pending, line)
            continue
        endif

        " don't join lines with word characters
        " but first join pending lines to previous output line
        let joined[-1] = s:join_pending(joined[-1], pending)
        let pending = []
        call add(joined, line)
    endfor

    " join remaining pending lines to last
    let joined[-1] = s:join_pending(joined[-1], pending)
    return joined
endfunction

function! s:join_pending(base, pending) abort
    return insert(a:pending, a:base, 0) " TODO: simplify this
endfunction

" TODO: limit later somehow?
" currently there's an issue where the full context is long enough so that the
" limit hits at one indent, but because some of the context lines are visible
" belowe the context we wouldn't have to limit in the first place
function! s:limit(lines, indent) abort
    " call context#util#echof('> limit', a:indent, len(a:lines))

    let max = g:context.max_per_indent
    if len(a:lines) <= max
        return a:lines
    endif

    let diff = len(a:lines) - max

    let limited = a:lines[: max/2-1]
    let ellipsis_line = [context#line#make(0, a:indent, repeat(' ', a:indent) . g:context.ellipsis)]
    call add(limited, ellipsis_line)
    call extend(limited, a:lines[-(max-1)/2 :])
    return limited
endif
endfunction
