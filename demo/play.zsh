#!/usr/bin/env zsh
#
# play.zsh - Scripted demo session: runs demo/shell.sh and types the demo with realistic timing.
#
# Recorded by `make demo`:  asciinema rec -c "zsh demo/play.zsh" demo/demo.cast
# Watch it live without recording:  zsh demo/play.zsh
#
emulate -L zsh
zmodload zsh/zpty zsh/datetime

ROOT=${0:A:h:h}
COLS=${COLUMNS:-$(tput cols)} ROWS=${LINES:-$(tput lines)}
TYPING_DELAY=${DEMO_TYPING_DELAY:-0.055}

relay() { local o; while zpty -r -t demo o 2>/dev/null; do print -rn -- "$o"; done }
drain() { local o; while zpty -r -t demo o 2>/dev/null; do :; done }
pause() {   # show output while waiting $1 seconds
  local end=$(( EPOCHREALTIME + $1 ))
  while (( EPOCHREALTIME < end )); do relay; sleep 0.03; done
}
type_() {   # type $1 one character at a time
  local c
  for c in ${(s::)1}; do zpty -w -n demo "$c"; pause $TYPING_DELAY; done
}
key() { zpty -w -n demo "$1"; pause ${2:-0.3}; }
ENTER=$'\n' TAB=$'\t'

# Start the demo shell off-screen, at the size of the recording terminal
zpty -b demo "$ROOT/demo/shell.sh"
sleep 2; drain
zpty -w demo "stty cols $COLS rows $ROWS"; sleep 0.5; drain
zpty -w -n demo $'\C-l'; sleep 0.3; drain
print -rn -- $'\e[H\e[2J'          # start the recording on a clean screen
zpty -w -n demo $'\C-l'; pause 0.8   # ... showing just the prompt

# Which cluster has this namespace?
type_ "kwhere payments";            pause 0.4; key $ENTER 2.5
type_ "kwhere -p payments";         pause 0.4; key $ENTER 2.5

# Switch cluster + default namespace, with per-cluster completion
type_ "kswitch staging -n pay";     pause 0.4; key $TAB 1; key $ENTER 2.5

# Open k9s in a namespace of another cluster
type_ "kopen prod -n ";             pause 0.3; key $TAB 1.5
type_ "pay";                        pause 0.3; key $TAB 0.6; key $ENTER 3
key q 1                             # quit k9s

# Only know the namespace? kopen finds the cluster
type_ "kopen -n monitoring";        pause 0.4; key $ENTER 2.5
type_ "3";                          pause 0.4; key $ENTER 3
key q 1.5

zpty -w demo "exit"; sleep 0.5; drain   # not shown in the recording
zpty -d demo
