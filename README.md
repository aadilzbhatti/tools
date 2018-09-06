# Set up [iTerm2](https://www.iterm2.com/) + [Oh-My-Zsh](https://github.com/robbyrussell/oh-my-zsh)
  - Download iTerm2, or if you have Homebrew: `brew cask install iterm2`
  - For Oh-My-Zsh: `sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"`
  - Configure settings in `~/.zshrc`
    - Favorite theme: `agnoster`
    - Install [Powerline](https://github.com/powerline/fonts) fonts
    - Then, in iTerm2 make sure to set font to "12pt Ubuntu Mono derivative Powerline"
  - https://stackoverflow.com/questions/6205157/iterm-2-how-to-set-keyboard-shortcuts-to-jump-to-beginning-end-of-line/29403520#29403520
  - https://unix.stackexchange.com/questions/295680/cannot-exec-bin-false-no-such-file-or-directory


# Set up [Homebrew](https://brew.sh/)
  - `/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"`
  - If you want all of the previously installed packages, run `brew bundle` in the directory with the `Brewfile` (this will take some time)
  - Otherwise, run `brew install python3`, `wget`, `vim` for starters
  - `brew install z`

# Download [Atom](https://atom.io/)
  - Run `apm install --packages-file atom-packages`

# Set up Vim
  - `brew install vim`, `brew install wget` if not done already
  - https://github.com/amix/vimrc
