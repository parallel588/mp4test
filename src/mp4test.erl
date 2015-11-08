-module(mp4test).
-export([main/1]).

main([Path] =_Args) ->
    io:format(video_parse:parse(Path)).
