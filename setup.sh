#!/bin/bash

# install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# add homebrew to your path
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/aadil/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# install Iterm2
brew install iterm2 --cask
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

## Install powerline fonts
git clone https://github.com/powerline/fonts.git --depth=1 
cd fonts 
./install.sh 
cd .. 
rm -rf fonts

## install other packages
brew install wget python3 vim z

# install vimrc
wget https://github.com/aadilzbhatti/tools/blob/master/vimrc ~/.vimrc
