# Editors' integration

We don't have any proper integration or official plugins for editors yet.

Here are a few ideas you can use to make your own flow.

## Vim

Split terminal vertically and open fast focused on build the expression.

```vim
nnoremap <Leader>ff :vsplit \| terminal fast "()" % <Left><Left><Left><Left><Left>
```

Or you can build a function:

```vim
function! s:Fast(args)
  let cmd = ''
  if !empty(b:ruby_project_root)
    let cmd .= 'cd ' . b:ruby_project_root . ' && '
  endif

  let cmd .= 'fast --no-color ' . a:args

  let custom_maker = neomake#utils#MakerFromCommand(cmd)
  let custom_maker.name = cmd
  let custom_maker.cwd = b:ruby_project_root
  let custom_maker.remove_invalid_entries = 0
  " e.g.:
  "   # path/to/file.rb:1141
  "   my_method(
  "     :boom,
  "     arg1: 1,
  "   )
  " %W# %f:%l -> start a multiline warning when the line matches '# path/file.rb:1234'
  " %-Z# end multiline warning on the next line that starts with '#'
  " %C%m continued multiline warning message
  let custom_maker.errorformat = '%W# %f:%l, %-Z#, %C%m'
  let enabled_makers = [custom_maker]
  update | call neomake#Make(0, enabled_makers) | echom "running: " . cmd
endfunction
command! -complete=file -nargs=1 Fast call s:Fast(<q-args>)
```

Check the conversation about vim integration [here](https://github.com/jonatas/fast/pull/16#issuecomment-555115606).
