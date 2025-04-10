#!/bin/bash

apt update
wget --no-check-certificate https://github.com/fastfetch-cli/fastfetch/releases/download/2.36.1/fastfetch-linux-amd64.deb
sudo dpkg -i fastfetch-linux-amd64.deb
rm fastfetch-linux-amd64.deb

# Create build directory and clone repo
mkdir -p ~/build
cd ~/build
git clone https://github.com/christitustech/mybash
cd mybash
./setup.sh

# Create starship config with proper formatting
cat > ~/.config/starship.toml << 'EOF'
format = """
[](#3B4252)\
$python\
$username\
[](bg:#434C5E fg:#3B4252)\
$directory\
[](fg:#434C5E bg:#5C6370)\
$git_branch\
$git_status\
[](fg:#5C6370 bg:#7F848E)\
$c\
$elixir\
$elm\
$golang\
$haskell\
$java\
$julia\
$nodejs\
$nim\
$rust\
[](fg:#7F848E bg:#5C6370)\
$docker_context\
[](fg:#5C6370 bg:#4C566A)\
$time\
[ ](fg:#4C566A)\
"""
command_timeout = 5000

[username]
show_always = true
style_user = "bg:#3B4252"
style_root = "bg:#3B4252"
format = '[$user ]($style)'

[directory]
style = "bg:#434C5E"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[c]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[docker_context]
symbol = " "
style = "bg:#5C6370"
format = '[ $symbol $context ]($style)$path'

[elixir]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[elm]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[git_branch]
symbol = ""
style = "bg:#5C6370"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#5C6370"
format = '[$all_status$ahead_behind ]($style)'

[golang]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[haskell]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[java]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[julia]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[nodejs]
symbol = ""
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[nim]
symbol = " "
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[python]
style = "bg:#3B4252"
format = '[(\($virtualenv\) )]($style)'

[rust]
symbol = ""
style = "bg:#7F848E"
format = '[ $symbol ($version) ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#4C566A"
format = '[ $time ]($style)'
EOF

echo "Starship configuration has been updated with gray theme"
