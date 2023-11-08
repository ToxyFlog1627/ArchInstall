" Plug config
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

" Plugins
call plug#begin()
Plug 'itchyny/lightline.vim'
Plug 'arcticicestudio/nord-vim'
call plug#end()

" Use true colors
if exists('+termguicolors')
    let &t_8f="\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b="\<Esc>[48;2;%lu;%lu;%lum"
    set termguicolors
endif

" Indent line
let g:indentLine_char = '▏'
let g:indentLine_setColors = 0

" Colorscheme 
colorscheme nord
set background=dark
hi Normal guibg=NONE ctermbg=NONE

" Lightline
set laststatus=2
set noshowmode
let g:lightline = { 'colorscheme': 'nord' }

" Settings
set incsearch
set tabstop=4
set softtabstop=4
set shiftwidth=4
syntax on
set number
set fileformat=unix
set nocompatible
set noswapfile
set clipboard=unnamedplus