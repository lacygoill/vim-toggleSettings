vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# FAQ {{{1

# Don't forget to properly handle repeated (dis)activations. {{{
#
# It's necessary when your (dis)activation  has a side effect like (re)setting a
# persistent variable.
#
# ---
#
# When you write a function  to activate/disactivate/toggle some state, do *not*
# assume it will only be used for repeated toggling.
# It can  also be  used for (accidental)  repeated activations,  or (accidental)
# repeated disactivations.
#
# There is no issue if the  function has no side effect.
# But  if   it  does  (e.g.  `g:ToggleSettingsAutoOpenFold()`   creates  a  `b:`
# variable), and doesn't handle repeated (dis)activations, you can experience an
# unexpected behavior.
#
# For example, let's assume the function saves in a variable some info necessary
# to restore the current state.
# If  you transit  to  the same  state  twice, the  1st time,  it  will work  as
# expected: the function will save the info about the current state, A, then put
# you in the new state B.
# But the  2nd time,  the function will  again save the  info about  the current
# state – now B – overwriting the info about A.
# So, when you will invoke it to restore A, you will, in effect, restore B.
#}}}
#   OK, but concretely, what should I avoid?{{{
#
# *Never* write this:
#
#     # at script level
#     var save: any
#     ...
#
#     # in :def function
#     if enable                       ✘
#         save = ...
#         │
#         └ save current state for future restoration
#         ...
#     else                            ✘
#         ...
#     endif
#
# Instead:
#
#     if enable && is_disabled        ✔
#         save = ...
#         ...
#     elseif !enable && is_enabled    ✔
#         ...
#     endif
#
# Note that  in this pseudo-code, you  don't really need `&&  is_enabled` in the
# `elseif` block, because it doesn't show any code with a side effect.
# Still, the  code is slightly more  readable when the 2  guards are constructed
# similarly.
# Besides, it  makes the  code more  future-proof; if  one of  the `if`/`elseif`
# blocks has a side effect now, there is  a good chance that, one day, the other
# one will *also* have a side effect.
#
# ---
#
# You have to write the right expressions for `is_disabled` and `is_enabled`.
# If you want  to toggle an option with  only 2 possible values –  e.g. 'on' and
# 'off' – then it's easy:
#
#     is_enabled = opt == 'on'
#     is_disabled = opt == 'off'
#
# But  if you  want to  toggle an  option with  more than  2 values  – e.g.  'a'
# (enabled), 'b' and 'c' (disabled) – then there is a catch.
# The assertions *must* be negative to handle  the case where the option has the
# unexpected value 'b'.
#
# For example, you should not write this:
#
#     is_enabled = opt == 'a'
#     is_disabled = opt == 'c'
#
# But this:
#
#                      vv
#     is_enabled = opt != 'c'
#     is_disabled = opt != 'a'
#                       ^^
#
# With the  first code, if `opt`  has the the value  'b' (set by accident  or by
# another plugin), your `if`/`elseif` blocks would never be run.
# With the  second code, if `opt`  has the value  'b', it will always  be either
# enabled (set to 'a') or disabled (set to 'c').
#}}}

# What is a proxy expression?{{{
#
# An expression that you inspect to determine  whether a state X is enabled, but
# which is never referred to in the definition of the latter.
#
# Example:
#
# When  we press  `[oq`,  the state  “local  value of  'formatprg'  is used”  is
# enabled; let's call this state X.
#
# When we disable X, `formatprg_save` is created inside `Formatprg()`.
# So,   to  determine   whether  X   is   enabled,  you   could  check   whether
# `formatprg_save` exists; if it does not, then X is enabled.
# But when you define what X is,  you don't need to refer to `formatprg_save` at
# any point;  so if  you're inspecting  `formatprg_save`, you're  using it  as a
# proxy expression; it's a proxy for the state X.
#}}}
#   Why is it bad to use one?{{{
#
# It works only under the assumption that  the state you're toggling can only be
# toggled via your mapping  (e.g. `coq`), which is not always  true; and even if
# it is true now, it may not be true in the future.
#
# For example, the non-existence of `formatprg_save` does not guarantee that the
# local value of `'formatprg'` is used.
# The local value could have been emptied  by a third-party plugin (or you could
# have done it  manually with a `:set[l]` command); in  which case, you're using
# the global value, and yet `formatprg_save` does not exist.
#}}}
#     When is it still ok to use one?{{{
#
# When the expression is *meant* to be used as a proxy, and is not ad-hoc.
#
# For example, in the past, we used a proxy expression for the matchparen module
# of `vim-matchup`;  we inspected  the value  of `g:matchup_matchparen_enabled`:
#
#     get(g:, "matchup_matchparen_enabled", v:false)
#
# It's meant  to be used as  a proxy to  check whether the matchparen  module of
# matchup is enabled.
#
# The alternative would be  to read the source code of  `vim-matchup` to get the
# name of  the autocmd which  implements the automatic highlighting  of matching
# words.
# But that  would be unreliable, because  it's part of the  implementation which
# may change at any time (e.g. after a refactoring).
# OTOH, the `g:` variable is reliable, because it's part of the interface of the
# plugin; as such, the plugin author should not change its name or remove it, at
# least if they care about backward compatibility.
#}}}

# I want to toggle between the global value and the local value of a buffer-local option.{{{
#}}}
#   Which one should I consider to be the “enabled” state?{{{
#
# The local value.
# It makes sense,  because usually when you  enable sth, you tend  to think it's
# special (e.g.  you enter a  temporary special mode);  the global value  is not
# special, it's common.
#}}}

# About the scrollbind feature: what's the relative offset?{{{
#
# It's the difference between the topline  of the current window and the topline
# of the other bound window.
#
# From `:help 'scrollopt'`:
#
#    > jump      Applies to the offset between two windows for vertical
#    >           scrolling.  This offset is the difference in the first
#    >           displayed line of the bound windows.
#
# And from `:help scrollbind-relative`:
#
#    > Each 'scrollbind' window keeps track of its "relative offset," which can be
#    > thought of as the difference between the current window's vertical scroll
#    > position and the other window's vertical scroll position.
#}}}
# What's the effect of the `jump` flag in `'scrollopt'`?{{{
#
# It's included by default; if you remove it, here's what happens:
#
#     # in a terminal with 24 lines
#     set scrollbind scrollopt=ver number
#     silent put =range(char2nr('a'), char2nr('z'))->map((_, v) => nr2char(v))->repeat(2)
#     botright vnew
#     silent put =range(char2nr('a'), char2nr('z'))->map((_, v) => nr2char(v))
#     windo :1
#     wincmd w
#
# Now, press:
#
#    - `jk`
#
#       Necessary to avoid what seems to be a bug,
#       where the second window doesn't scroll when you immediately press `G`.
#
#    - `G` to jump at the end of the buffer
#
#    - `C-w w` twice to focus the second window and come back
#
#       You don't need to press it twice to expose the behavior we're going to discuss;
#       once is enough;
#       twice just makes the effect more obvious.
#
# The relative offset is not 0 anymore, but 5.
# This is confirmed by the fact that  if you press `k` repeatedly to scroll back
# in the  first window, the  difference between the toplines  constantly remains
# equal to 5.
#
# When you reach the top of the buffer, the offset decreases down to 0.
# But when you press `j` to scroll down, the offset quickly gets back to 5.
#
# I don't know  how this behavior can  be useful; I find it  confusing, so don't
# remove `jump` from `'scrollopt'`.
#
# Note that this effect is cancelled if you also set `'cursorbind'`.
#
# For more info, see:
#
#     :help 'scrollbind'
#     :help 'scrollopt'
#     :help scroll-binding
#     :help scrollbind-relative
#}}}

# Init {{{1

import 'lg.vim'
import 'lg/mapping.vim'

const AOF_LHS2NORM: dict<string> = {
    j: 'j',
    k: 'k',
    '<Down>': "\<Down>",
    '<Up>': "\<Up>",
    '<C-D>': "\<C-D>",
    '<C-U>': "\<C-U>",
    gg: 'gg',
    G: 'G',
}

const SMC_BIG: number = 3'000

const HL_TIME: number = 250

var formatprg_save: dict<string>
var hl_yanked_text: bool
var scrollbind_save: dict<dict<bool>>
var synmaxcol_save: dict<number>

# Commands {{{1

# Don't write `<bang><bang>0`.{{{
#
# Without a bang, you would get `0`.
# With a bang, you would get `false`.
# IOW, you would never enable the feature.
#}}}
command -bar -bang FoldAutoOpen g:ToggleSettingsAutoOpenFold(<bang>0 ? false : true)

# Autocmds {{{1

augroup HlYankedText
    autocmd!
    autocmd TextYankPost * {
        if HlYankedText('is_active')
            AutoHlYankedText()
        endif
    }
augroup END

# Statusline Flags {{{1

const SFILE: string = expand('<sfile>:p')
augroup HoistToggleSettings
    autocmd!
    autocmd User MyFlags g:StatusLineFlag('global',
        \ '%{get(g:, "my_verbose_errors", v:false) ? "[Verb]" : ""}', 6, SFILE .. ':' .. expand('<sflnum>'))
    autocmd User MyFlags g:StatusLineFlag('global',
        \ '%{get(g:, "debugging", v:false) ? "[Debug]" : ""}', 9, SFILE .. ':' .. expand('<sflnum>'))
    autocmd User MyFlags g:StatusLineFlag('buffer',
        \ '%{exists("b:auto_open_fold_mappings") ? "[AOF]" : ""}', 45, SFILE .. ':' .. expand('<sflnum>'))
    autocmd User MyFlags g:StatusLineFlag('buffer',
        \ '%{&l:synmaxcol > 999 ? "[smc>999]" : ""}', 46, SFILE .. ':' .. expand('<sflnum>'))
    autocmd User MyFlags g:StatusLineFlag('buffer',
        \ '%{&l:nrformats =~# "alpha" ? "[nf~alpha]" : ""}', 47, SFILE .. ':' .. expand('<sflnum>'))
augroup END

if exists('#MyStatusline#VimEnter')
    doautocmd <nomodeline> MyStatusline VimEnter
endif

# Functions {{{1
def ToggleSettings( #{{{2
    key: string,
    option: string,
    reset = '',
    test = ''
)
    var set_cmd: string
    var reset_cmd: string
    if reset == ''
        [set_cmd, reset_cmd] = [
            'setlocal ' .. option,
            'setlocal no' .. option,
        ]

        var toggle_cmd: string = 'if &l:' .. option
            .. ' <Bar>    execute ' .. string(reset_cmd)
            .. ' <Bar> else'
            .. ' <Bar>    execute ' .. string(set_cmd)
            .. ' <Bar> endif'

        execute 'nmap <unique> [o' .. key .. ' <Plug>([o' .. key .. ')'
        execute 'nmap <unique> ]o' .. key .. ' <Plug>(]o' .. key .. ')'
        execute 'nmap <unique> co' .. key .. ' <Plug>(co' .. key .. ')'

        execute 'nnoremap <Plug>([o' .. key .. ') <ScriptCmd>' .. set_cmd .. '<CR>'
        execute 'nnoremap <Plug>(]o' .. key .. ') <ScriptCmd>' .. reset_cmd .. '<CR>'
        execute 'nnoremap <Plug>(co' .. key .. ') <ScriptCmd>' .. toggle_cmd .. '<CR>'

    else
        [set_cmd, reset_cmd] = [option, reset]

        var rhs3: string = '     if ' .. test
            .. ' <Bar>    execute ' .. string(reset_cmd)
            .. ' <Bar> else'
            .. ' <Bar>    execute ' .. string(set_cmd)
            .. ' <Bar> endif'

        execute 'nmap <unique> [o' .. key .. ' <Plug>([o' .. key .. ')'
        execute 'nmap <unique> ]o' .. key .. ' <Plug>(]o' .. key .. ')'
        execute 'nmap <unique> co' .. key .. ' <Plug>(co' .. key .. ')'

        execute 'nnoremap <Plug>([o' .. key .. ') <ScriptCmd>' .. set_cmd .. '<CR>'
        execute 'nnoremap <Plug>(]o' .. key .. ') <ScriptCmd>' .. reset_cmd .. '<CR>'
        execute 'nnoremap <Plug>(co' .. key .. ') <ScriptCmd>' .. rhs3 .. '<CR>'
    endif
enddef

def g:ToggleSettingsAutoOpenFold(enable: bool) #{{{2
    if enable && !exists('b:auto_open_fold_mappings')
        if foldclosed('.') >= 0
            normal! zvzz
        endif
        b:auto_open_fold_mappings = AOF_LHS2NORM
            ->keys()
            ->mapping.Save('n', true)
        for lhs: string in AOF_LHS2NORM->keys()
            # Why do you open all folds with `zR`?{{{
            #
            # This is necessary when you scroll backward.
            #
            # Suppose you are  on the first line of  a fold and you move  one line back;
            # your cursor will *not* land on the previous line, but on the first line of
            # the previous fold.
            #}}}
            # Why `:silent!` before `:normal!`?{{{
            #
            # If you're on  the last line and  you try to move  forward, it will
            # fail, and the rest of the sequence (`zMzv`) will not be processed.
            # Same issue if you try to move backward while on the first line.
            # `silent!` makes sure that the whole sequence is processed no matter what.
            #}}}
            # Why `substitute(...)`?{{{
            #
            # To prevent some keys from being translated by `:nnoremap`.
            # E.g., you don't want `<C-U>` to be translated into a literal `C-u`.
            # Because  when you  press the  mapping, `C-u`  would not  be passed
            # to  `MoveAndOpenFold()`;  instead,  it  would be  pressed  on  the
            # command-line.
            #}}}
            execute printf(
                'nnoremap <buffer><nowait> %s <ScriptCmd>MoveAndOpenFold(%s, v:count)<CR>',
                    lhs,
                    lhs->substitute('^<\([^>]*>\)$', '<lt>\1', '')->string()
            )
        endfor
    elseif !enable && exists('b:auto_open_fold_mappings')
        mapping.Restore(b:auto_open_fold_mappings)
        unlet! b:auto_open_fold_mappings
    endif

    # Old Code:{{{
    #
    #     def g:ToggleSettingsAutoOpenFold(enable: bool)
    #         if enable && &foldopen != 'all'
    #             fold_options_save = {
    #                 open: &foldopen,
    #                 close: &foldclose,
    #                 enable: &foldenable,
    #                 level: &foldlevel,
    #                 }
    #             # Consider setting 'foldnestmax' if you use 'indent'/'syntax' as a folding method.{{{
    #             #
    #             # If you set the local value of  'foldmethod' to 'indent' or 'syntax', Vim
    #             # will automatically fold the buffer according to its indentation / syntax.
    #             #
    #             # It can lead to deeply nested folds.  This can be annoying when you have
    #             # to open  a lot of  folds to  read the contents  of a line.
    #             #
    #             # One way to tackle this issue  is to reduce the value of 'foldnestmax'.
    #             # By default  it's 20 (which is  the deepest level of  nested folds that
    #             # Vim can produce with these 2 methods  anyway).  If you set it to 1, Vim
    #             # will only produce folds for the outermost blocks (functions/methods).
    #             #}}}
    #             &:foldclose = 'all'
    #             &:foldopen = 'all'
    #             &:foldenable = true
    #             &:foldlevel = 0
    #         elseif !enable && &foldopen == 'all'
    #             for op: string in keys(fold_options_save)
    #                 execute '&fold' .. op .. ' = fold_options_save.' .. op
    #             endfor
    #             normal! zMzv
    #             fold_options_save = {}
    #         endif
    #     enddef
    #     fold_options_save: dict<any>
    #     ToggleSettings(
    #         'z',
    #         'g:ToggleSettingsAutoOpenFold(true)',
    #         'g:ToggleSettingsAutoOpenFold(false)',
    #         '&foldopen == "all"',
    #     )
    #}}}
    #   What did it do?{{{
    #
    # It toggled  a *global* auto-open-fold  state, by (re)setting  some folding
    # options, such as `'foldopen'` and `'foldclose'`.
    #}}}
    #   Why don't you use it anymore?{{{
    #
    # In practice, that's never what I want.
    # I want to toggle a *local* state (local to the current buffer).
    #
    # ---
    #
    # Besides, suppose you want folds to be opened automatically in a given window.
    # You enable the feature.
    # After a while you're finished, and close the window.
    # Now you need to restore the state as it was before enabling it.
    # This is fiddly.
    #
    # OTOH, with a local state, you don't have anything to restore after closing
    # the window.
    #}}}
enddef

# Warning: Do *not* change the name of this function.{{{
#
# If  you really  want  to, then  you'll  need to  refactor  other scripts;  run
# `:vimgrep` over all our Vimscript files to find out where we refer to the name
# of this function.
#}}}
# Warning: Folds won't be opened/closed if the next line is in a new fold which is not closed.{{{
#
# This is because we run `normal! zMzv`  iff the foldlevel has changed, or if we
# get on a line in a closed fold.
#}}}
# Why don't you fix this?{{{
#
# Not sure how to fix this.
# Besides, I kinda like the current behavior.
# If you press `zR`, you can move with `j`/`k` in the buffer without folds being closed.
# If you press `zM`, folds are opened/closed automatically again.
# It gives you a little more control about this feature.
#}}}
def MoveAndOpenFold(lhs: string, cnt: number)
    # We want to pass a count if we've pressed `123G`.
    # But we don't want any count if we've just pressed `G`.
    var scnt: string = (cnt != 0 ? cnt : '')
    var old_foldlevel: number = foldlevel('.')
    var old_winline: number = winline()
    if lhs == 'j' || lhs == '<Down>'
        execute 'normal! ' .. scnt .. 'gj'
        if &filetype == 'markdown' && getline('.') =~ '^#\+$'
            return
        endif
        var is_in_a_closed_fold: bool = foldclosed('.') >= 0
        var new_foldlevel: number = foldlevel('.')
        var level_changed: bool = new_foldlevel != old_foldlevel
        # need to  check `level_changed` to handle  the case where we  move from
        # the end of a nested fold to the next line in the containing fold
        if (is_in_a_closed_fold || level_changed) && DoesNotDistractInGoyo()
            normal! zMzv
            # Rationale:{{{
            #
            # I don't  mind the distance between  the cursor and the  top of the
            # window changing unexpectedly after pressing `j` or `k`.
            # In fact, the  way it changes now  lets us see a good  portion of a
            # fold when we enter it, which I like.
            #
            # However, in goyo mode, it's distracting.
            #}}}
            if get(g:, 'in_goyo_mode', false)
                FixWinline(old_winline, 'j')
            endif
        endif
    elseif lhs == 'k' || lhs == '<Up>'
        execute 'normal! ' .. scnt .. 'gk'
        if &filetype == 'markdown' && getline('.') =~ '^#\+$'
            return
        endif
        var is_in_a_closed_fold: bool = foldclosed('.') >= 0
        var new_foldlevel: number = foldlevel('.')
        var level_changed: bool = new_foldlevel != old_foldlevel
        # need to  check `level_changed` to handle  the case where we  move from
        # the start of a nested fold to the previous line in the containing fold
        if (is_in_a_closed_fold || level_changed) && DoesNotDistractInGoyo()
            # `silent!` to make sure all the keys are pressed, even if an error occurs
            silent! normal! gjzRgkzMzv
            if get(g:, 'in_goyo_mode', false)
                FixWinline(old_winline, 'k')
            endif
        endif
    else
        execute 'silent! normal! zR' .. scnt .. AOF_LHS2NORM[lhs] .. 'zMzv'
    endif
enddef

def DoesNotDistractInGoyo(): bool
    # In goyo mode, opening a fold containing only a long comment is distracting.
    # Because we only care about the code.
    if !get(g:, 'in_goyo_mode', false) || &filetype == 'markdown'
        return true
    endif
    var cml: string = &commentstring->matchstr('\S*\ze\s*%s')
    # note that we allow opening numbered folds (because usually those can contain code)
    var foldmarker: string = '\%(' .. split(&l:foldmarker, ',')->join('\|') .. '\)'
    return getline('.') !~ '^\s*\V' .. escape(cml, '\') .. '\m.*' .. foldmarker .. '$'
enddef

def FixWinline(old: number, dir: string)
    var now: number = winline()
    if dir == 'k'
        # getting one line closer from the top of the window is expected; nothing to fix
        if now == old - 1
            return
        endif
        # if we were not at the top of the window before pressing `k`
        if old > (&scrolloff + 1)
            normal! zt
            var new: number = (old - 1) - (&scrolloff + 1)
            if new != 0
                execute 'normal! ' .. new .. "\<C-Y>"
            endif
        # old == (&scrolloff + 1)
        else
            normal! zt
        endif
    elseif dir == 'j'
        # getting one line closer from the bottom of the window is expected; nothing to fix
        if now == old + 1
            return
        endif
        # if we were not at the bottom of the window before pressing `j`
        if old < (winheight(0) - &scrolloff)
            normal! zt
            var new: number = (old + 1) - (&scrolloff + 1)
            if new != 0
                execute 'normal! ' .. new .. "\<C-Y>"
            endif
        # old == (winheight(0) - &scrolloff)
        else
            normal! zb
        endif
    endif
enddef

def Conceallevel(enable: bool) #{{{2
    if enable
        &l:conceallevel = 0
        ToggleKittyLigatures(enable)
    else
        # Why toggling between `0` and `2`, instead of `0` and `3` like everywhere else?{{{
        #
        # In a markdown file, we want to see `cchar`.
        # For example, it's  useful to see a marker denoting  a concealed answer
        # to a question.
        # It could also be useful to pretty-print some logical/math symbols.
        #}}}
        &l:conceallevel = &filetype == 'markdown' ? 2 : 3
        ToggleKittyLigatures(enable)
    endif
    echo '[conceallevel] ' .. &l:conceallevel
enddef

def ToggleKittyLigatures(enable: bool)
    if &term !~ 'kitty'
        return
    endif
    system('kitty @ disable-ligatures --all ' .. (enable ? 'always' : 'cursor'))
enddef

def Debugging(enable: bool) #{{{2
# There is `v:profiling`, but there is no `v:debugging`.
# The latter  would be handy  to temporarily disable command-line  mode mappings
# and autocmds which  can interfere (i.e. add *a lot*  of irrelevant noise) when
# we are in debug mode.  Let's emulate the variable with `g:debugging`.
    g:debugging = enable
    # Make sure we never debug an autocmd listening to `FocusLost`; it's too confusing.{{{
    #
    # In debug mode, if you temporarily  focus a different window program, a new
    # frame is added on the stack for your autocmds listening to `FocusLost`.
    # You probably don't care about the code they run; it's unexpected.
    #
    # Even more confusing, when Vim loses the focus, all mappings are disabled.
    #
    #     $ vim -Nu <(tee <<'EOF'
    #         vim9script
    #         &t_TI = ''
    #         &t_TE = ''
    #
    #         &t_fe = "\<Esc>[?1004h"
    #         &t_fd = "\<Esc>[?1004l"
    #         autocmd FocusLost * eval 1 + 2
    #
    #         cnoremap xx yy
    #         debug edit
    #     EOF
    #     )
    #
    #     # Focus another pane/window, get back, and press "xx"
    #     # Expected: yy
    #     # Actual: xx
    #
    # As a one-shot workaround, you can execute `> finish` to step over whatever
    # code is run by the autocmd.  That should allow the mappings to work again,
    # and pop the most recent (and undesirable) frame from the stack.
    #
    # But that's still too cumbersome and distracting.
    # So we simply  disable `FocusLost`.
    #}}}
    &eventignore = enable ? 'FocusLost' : ''
    redrawtabline
enddef

def EditHelpFile(allow: bool) #{{{2
    if &filetype != 'help'
        return
    endif

    if allow && &buftype == 'help'
        &l:modifiable = true
        &l:readonly = false
        &l:buftype = ''

        nnoremap <buffer><nowait> <CR> 80<Bar>

        var keys: list<string> =<< trim END
            p
            q
            u
        END
        for key: string in keys
            execute 'silent unmap <buffer> ' .. key
        endfor

        for pat: string in keys
                 ->map((_, v: string) =>
                        '|\s*execute\s*''[nx]unmap\s*<buffer>\s*' .. v .. "'")
            b:undo_ftplugin = b:undo_ftplugin->substitute(pat, '', 'g')
        endfor

        echo 'you CAN edit the file'

    elseif !allow && &buftype != 'help'
        if &modified
            Error('save the buffer first')
            return
        endif
        #
        # don't reload the buffer before setting `'buftype'`; it would change the cwd (`vim-cwd`)
        &l:modifiable = false
        &l:readonly = true
        &l:buftype = 'help'
        # reload ftplugin
        edit
        echo 'you can NOT edit the file'
    endif
enddef

def Formatprg(scope: string) #{{{2
    if scope == 'local' && &l:formatprg == ''
        var bufnr: number = bufnr('%')
        if formatprg_save->has_key(bufnr)
            &l:formatprg = formatprg_save[bufnr]
            unlet! formatprg_save[bufnr]
        endif
    elseif scope == 'global' && &l:formatprg != ''
        # save the local value on a per-buffer basis
        formatprg_save[bufnr('%')] = &l:formatprg
        # clear the local value so that the global one is used
        set formatprg<
    endif
    echo '[formatprg] ' .. (
            !empty(&l:formatprg)
            ? &l:formatprg .. ' (local)'
            : &g:formatprg .. ' (global)'
        )
enddef

def HlYankedText(action: string): bool #{{{2
    if action == 'is_active'
        return hl_yanked_text
    elseif action == 'enable'
        hl_yanked_text = true
    elseif action == 'disable'
        hl_yanked_text = false
    endif
    return false
enddef

def AutoHlYankedText()
    try
        # don't highlight anything if we didn't copy anything
        if v:event.operator != 'y'
        # don't highlight anything if Vim has copied the visual selection in `*`
        # after we leave visual mode
        || v:event.regname == '*'
            return
        endif

        var text: list<string> = v:event.regcontents
        var type: string = v:event.regtype
        var lnum: number = line('.')
        var vcol: number = virtcol([lnum, col('.') - 1]) + 1
        var pat: string
        if type == 'v'
            # Alternative to avoid the quantifier:{{{
            #
            #     var height: number = len(text)
            #     ...
            #     if height == 1
            #         pat = '\%' .. lnum .. 'l'
            #            .. '\%>' .. (vcol - 1) .. 'v'
            #            .. '\%<' .. (vcol + strcharlen(text[0])) .. 'v'
            #     elseif height == 2
            #         pat = '\%' .. lnum .. 'l'
            #            .. '\%>' .. (vcol - 1) .. 'v'
            #            .. '\|'
            #            .. '\%' .. (lnum + 1) .. 'l'
            #            .. '\%<' .. (strcharlen(text[1]) + 1) .. 'v'
            #     else
            #         pat = '\%' .. lnum .. 'l'
            #            .. '\%>' .. (vcol - 1) .. 'v'
            #            .. '\|'
            #            .. '\%>' .. lnum .. 'l\%<' .. (lnum + height - 1) .. 'l'
            #            .. '\|'
            #            .. '\%' .. (lnum + height - 1) .. 'l'
            #            .. '\%<' .. (strcharlen(text[-1]) + 1) .. 'v'
            #     endif
            #}}}
            pat = '\%' .. lnum .. 'l\%' .. vcol .. 'v'
                .. '\_.\{' .. text->join("\n")->strcharlen() .. '}'
        elseif type == 'V'
            pat = '\%>' .. (lnum - 1) .. 'l'
               .. '\%<' .. (lnum + len(text)) .. 'l'
        elseif type =~ "\<C-V>" .. '\d\+'
            var width: number = type->matchstr("\<C-V>" .. '\zs\d\+')->str2nr()
            var height: number = len(text)
            pat = '\%>' .. (lnum - 1) .. 'l'
               .. '\%<' .. (lnum + height) .. 'l'
               .. '\%>' .. (vcol - 1) .. 'v'
               .. '\%<' .. (vcol + width) .. 'v'
        endif

        hl_yanked_text_id = matchadd('IncSearch', pat, 0, -1)
        timer_start(HL_TIME, (_) =>
            hl_yanked_text_id != 0 && matchdelete(hl_yanked_text_id))
    catch
        lg.Catch()
    endtry
enddef
var hl_yanked_text_id: number

def Matchparen(enable: bool) #{{{2
    var matchparen_is_enabled: bool = exists('#matchparen')

    if enable && !matchparen_is_enabled
        MatchParen on
    elseif !enable && matchparen_is_enabled
        MatchParen off
    endif

    echo '[matchparen] ' .. (exists('#matchparen') ? 'ON' : 'OFF')
enddef

def Scrollbind(enable: bool) #{{{2
    var winid: number = win_getid()
    if enable && !&l:scrollbind
        scrollbind_save[winid] = {
            cursorbind: &l:cursorbind,
            cursorline: &l:cursorline,
            foldenable: &l:foldenable
        }
        &l:scrollbind = true
        &l:cursorbind = true
        &l:cursorline = true
        &l:foldenable = false
        # not necessary  because we  already set  `'cursorbind'` which  seems to
        # have the same effect, but it doesn't harm
        syncbind
    elseif !enable && &l:scrollbind
        &l:scrollbind = false
        if scrollbind_save->has_key(winid)
            &l:cursorbind = get(scrollbind_save[winid], 'cursorbind', &l:cursorbind)
            &l:cursorline = get(scrollbind_save[winid], 'cursorline', &l:cursorline)
            &l:foldenable = get(scrollbind_save[winid], 'foldenable', &l:foldenable)
            unlet! scrollbind_save[winid]
        endif
    endif
enddef

def Synmaxcol(enable: bool) #{{{2
    var bufnr: number = bufnr('%')

    if enable && &l:synmaxcol != SMC_BIG
        synmaxcol_save[bufnr] = &l:synmaxcol
        &l:synmaxcol = SMC_BIG

    elseif !enable && &l:synmaxcol == SMC_BIG
        if synmaxcol_save->has_key(bufnr)
            &l:synmaxcol = synmaxcol_save[bufnr]
            unlet! synmaxcol_save[bufnr]
        endif
    endif
enddef

def Virtualedit(enable: bool) #{{{2
    if enable
        &virtualedit = 'all'
    else
        &virtualedit = get(g:, '_ORIG_VIRTUALEDIT', &virtualedit)
    endif
enddef

def Nowrapscan(enable: bool) #{{{2
    # Why do you inspect `'wrapscan'` instead of `'whichwrap'`?{{{
    #
    # Well, I think we  need to choose one of them;  can't inspect both, because
    # we could be in an unexpected state  where one of the option has been reset
    # manually (or by another plugin) but not the other.
    #
    # And we can't choose `'wrapscan'`.
    # If the  latter was reset  manually, the function  would fail to  toggle it
    # back on.
    #}}}
    if enable && &wrapscan
        # Why clearing `'whichwrap'` too?{{{
        #
        # It can cause the same issue as `'wrapscan'`.
        # To stop, a recursive macro may need an error to be given; however:
        #
        #    - this error may be triggered by an `h` or `l` motion
        #    - `'whichwrap'` suppresses this error if its value contains `h` or `l`
        #}}}
        whichwrap_save = &whichwrap
        &wrapscan = false
        &whichwrap = ''
    elseif !enable && !&wrapscan
        if whichwrap_save != ''
            &whichwrap = whichwrap_save
            whichwrap_save = ''
        endif
        &wrapscan = true
    endif
enddef
var whichwrap_save: string

def Error(msg: string) #{{{2
    echohl ErrorMsg
    echomsg msg
    echohl NONE
enddef
# }}}1
# Mappings {{{1
# 2 {{{2

ToggleSettings('P', 'previewwindow')
ToggleSettings('h', 'hlsearch')
ToggleSettings('i', 'list')
ToggleSettings('w', 'wrap')

# 4 {{{2

ToggleSettings(
    '<C-D>',
    'Debugging(true)',
    'Debugging(false)',
    'get(g:, "debugging")',
)

ToggleSettings(
    '<Space>',
    'set diffopt+=iwhiteall',
    'set diffopt-=iwhiteall',
    '&diffopt =~ "iwhiteall"',
)

ToggleSettings(
    'D',
    # `windo diffthis` would be simpler but might also change the currently focused window.
    'range(1, winnr("$"))->map((_, v: number) => win_execute(win_getid(v), "diffthis"))',
    'diffoff! <Bar> normal! zv',
    '&l:diff',
)

# `$MYVIMRC` is empty when we start with `-Nu /tmp/vimrc`.
var Cursorline: func
if $MYVIMRC != ''
    import $MYVIMRC as vimrc
    Cursorline = vimrc.Cursorline
    # Do *not* use `]L`: it's already taken to move to the last entry in the location list.
    ToggleSettings(
        'L',
        'Cursorline(true)',
        'Cursorline(false)',
        '&l:cursorline',
    )
endif

ToggleSettings(
    'S',
    '&l:spelllang = "fr" <Bar> echo "[spelllang] FR"',
    '&l:spelllang = "en" <Bar> echo "[spelllang] EN"',
    '&l:spelllang == "fr"',
)

ToggleSettings(
    'V',
    'g:my_verbose_errors = true <Bar> redrawtabline',
    'g:my_verbose_errors = false <Bar> redrawtabline',
    'get(g:, "my_verbose_errors", false)',
)

# it's useful to temporarily disable `'wrapscan'` before executing a recursive macro,
# to be sure it's not stuck in an infinite loop
ToggleSettings(
    'W',
    'Nowrapscan(true)',
    'Nowrapscan(false)',
    '!&wrapscan',
)

# How is it useful?{{{
#
# When we select a column of `a`'s, it's useful to press `g C-a` and get all the
# alphabetical characters from `a` to `z`.
#
# ---
#
# We  use `a`  as the  suffix  for the  lhs,  because it's  easier to  remember:
# `*a*lpha`, `C-*a*`, ...
#}}}
ToggleSettings(
    'a',
    'setlocal nrformats+=alpha',
    'setlocal nrformats-=alpha',
    'split(&l:nrformats, ",")->index("alpha") >= 0',
)

# Note: The conceal level is not a boolean state.{{{
#
# `'conceallevel'` can have 4 different values.
# But it doesn't cause any issue, because we still treat it as a boolean option.
# We are only interested in 2 levels: 0 and 3 (or 2 in a markdown file).
#}}}
ToggleSettings(
    'c',
    'Conceallevel(true)',
    'Conceallevel(false)',
    '&l:conceallevel == 0',
)

ToggleSettings(
    'd',
    'diffthis',
    'diffoff <Bar> normal! zv',
    '&l:diff',
)

ToggleSettings(
    'e',
    'EditHelpFile(true)',
    'EditHelpFile(false)',
    '&buftype == ""',
)

ToggleSettings(
    'm',
    'Synmaxcol(true)',
    'Synmaxcol(false)',
    '&l:synmaxcol == ' .. SMC_BIG,
)

# Alternative:{{{
# The following mapping/function allows to cycle through 3 states:
#
#    1. nonumber + norelativenumber
#    2. number   +   relativenumber
#    3. number   + norelativenumber
#
# ---
#
#     nnoremap <unique> con <ScriptCmd>Numbers()<CR>
#
#     def Numbers()
#         # The key '01' (state) is not necessary because no command in the dictionary
#         # brings us to it.
#         # However, if we got in this state by accident, hitting the mapping would give
#         # an error (E716: Key not present in Dictionary).
#         # So, we include it, and give it a value which brings us to state '11'.
#
#         execute {
#             falsefalse: '[&l:number, &l:relativenumber] = [true, true]',
#             truetrue: '&l:relativenumber = false',
#             falsetrue: '&l:number = false',
#             truefalse: '[&l:number, &l:relativenumber] = [false, false]',
#         }[&l:number .. &l:relativenumber]
#     enddef
#}}}
ToggleSettings(
    'n',
    '&l:number = true',
    '&l:number = false',
    '&l:number',
)

ToggleSettings(
    'p',
    'Matchparen(true)',
    'Matchparen(false)',
    'exists("#matchparen")',
)

# `gq`  is currently  used to  format comments,  but it  can also  be useful  to
# execute formatting tools such as `js-beautify` in html/css/js files.
ToggleSettings(
    'q',
    'Formatprg("local")',
    'Formatprg("global")',
    '&l:formatprg != ""',
)

ToggleSettings(
    'r',
    'Scrollbind(true)',
    'Scrollbind(false)',
    '&l:scrollbind',
)

ToggleSettings(
    's',
    '&l:spell = true',
    '&l:spell = false',
    '&l:spell',
)

ToggleSettings(
    't',
    'b:foldtitle_full = true <Bar> redraw!',
    'b:foldtitle_full = false <Bar> redraw!',
    'get(b:, "foldtitle_full", false)',
)

ToggleSettings(
    'v',
    'Virtualedit(true)',
    'Virtualedit(false)',
    '&virtualedit == "all"',
)

ToggleSettings(
    'y',
    'HlYankedText("enable")',
    'HlYankedText("disable")',
    'HlYankedText("is_active")',
)

# Vim uses `z` as a prefix to build all fold-related commands in normal mode.
ToggleSettings(
    'z',
    'g:ToggleSettingsAutoOpenFold(false)',
    'g:ToggleSettingsAutoOpenFold(true)',
    'maparg("j", "n", false, true)->get("rhs", "") !~ "MoveAndOpenFold"'
)
