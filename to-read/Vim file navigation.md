---
title: Vim file navigation
---

author:: PetePete

source:: [Vim file navigation](https://stackoverflow.com/questions/1445992/vim-file-navigation)

clipped:: [[2023-12-06]]

published:: 

#resources #to_read

Save this answer.

Show activity on this post.

I don't find drilling down into subdirectories via plain old `:e` to be that cumbersome given a decent configuration for tab-completion.

Look into the `'wildmenu'` option to have Vim show a list of completions (filenames) in the modeline above the commandline. You can change the `'wildmode'` option to further configure the kind of tab-completion Vim will do.

Personally I use `:set wildmode=full`.

My workflow is like this:

1.  `:cd` into the toplevel directory of my project.
2.  To open file `foo/bar/baz`:
    
    -   Simplest scenario: type `:e f<tab>b<tab>b<tab><enter>`.
        
    -   If there are more than one file starting with `b` in one of those directories you might have to do a `<left>` or `<right>` or another `<tab>` on the keyboard to jump between them (or type a few more letters to disambiguate).
        
    -   Worst-case scenario there are files and directories that share a name and you need to drill down into the directory. In this case tab-complete the directory name and then type `*<tab>` to drill down.
        
3.  Open 2 or 3 windows and open files in all of them as needed.
4.  Once a file is open in a buffer, don't kill the buffer. Leave it open in the background when you open new files. Just `:e` a new file in the same window.
5.  Then, use `:b <tab>` to cycle through buffers that are already open in the background. If you type `:b foo<tab>` it will match only against currently-open files that match `foo`.

I also use these mappings to make it easier to open new windows and to jump between them because it's something I do so often.

```
" Window movements; I do this often enough to warrant using up M-arrows on this"
nnoremap <M-Right> <C-W><Right>
nnoremap <M-Left> <C-W><Left>
nnoremap <M-Up> <C-W><Up>
nnoremap <M-Down> <C-W><Down>

" Open window below instead of above"
nnoremap <C-W>N :let sb=&sb<BAR>set sb<BAR>new<BAR>let &sb=sb<CR>

" Vertical equivalent of C-w-n and C-w-N"
nnoremap <C-w>v :vnew<CR>
nnoremap <C-w>V :let spr=&spr<BAR>set nospr<BAR>vnew<BAR>let &spr=spr<CR>

" I open new windows to warrant using up C-M-arrows on this"
nmap <C-M-Up> <C-w>n
nmap <C-M-Down> <C-w>N
nmap <C-M-Right> <C-w>v
nmap <C-M-Left> <C-w>V
```

It takes me a matter of seconds to open Vim, set up some windows and open a few files in them. Personally I have never found any of the third-party file-browsing scripts to be very useful.
