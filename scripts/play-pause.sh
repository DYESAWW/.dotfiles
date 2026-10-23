#!/usr/bin/env bash

OUTPUT=$(playerctl --player=spotify status)
if [[ ${OUTPUT} == "Playing" ]]
then
    playerctl --player=spotify,vlc,%any play-pause
else
    playerctl --player=vlc,%any,spotify play-pause
fi
