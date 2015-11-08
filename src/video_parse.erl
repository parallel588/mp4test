-module(video_parse).
-export([parse/1]).

-define(CONTAINER_BOX, [
                        "moov", "trak", "edts", "mdia", "minf", "dinf", "stbl", "mvex",
                        "moof", "traf", "mfra", "skip", "meta", "ipro", "sinf"
                       ]).

-record(mp4_raw_box, {
          type,
          size_base,
          start,
          entries}).

-record(stsd_entry, {
          type,
          size,
          height,
          width,
          horiz_res,
          vert_res,
          entries
         }).

-record(avc_entry, {
          size, 
          version,
          profile_indication,
          profile_compatibility,
          level
         }).

%% Start parse
parse(Path) ->
    io:format("Start !~n"),
    io:format("read file ~p\n", [Path]),
    io:format("---------------------------------------~n"),
    {ok, File} = file:open(Path, [read,binary,raw]),
    RawBoxes = parse_mp4(File),

    [AVC|_] = lists:flatten(parse_boxes(RawBoxes, File)),
    io:format("Profile: ~w \nLevel:  ~w \nHeigh x Width: ~wx~w \nHoriz x Vert resolution: ~wx~w \n",
              [
               AVC#stsd_entry.entries#avc_entry.profile_indication,
               AVC#stsd_entry.entries#avc_entry.level,
               AVC#stsd_entry.height,
               AVC#stsd_entry.width,
               AVC#stsd_entry.horiz_res,
               AVC#stsd_entry.vert_res
              ]),
    io:format("---------------------------------------~n"),
    io:format("Finish \n").

%% Parse MP4 container
parse_mp4(IoDevice) ->
    read_boxes(IoDevice).

%% Box is container
isContainer(Box) ->
    lists:member(Box#mp4_raw_box.type, ?CONTAINER_BOX).

%% Read MP4 Boxes
read_boxes(IoDevice) ->
    read_boxes(IoDevice, 0, 0, []).

read_boxes(IoDevice, Box) ->
    read_boxes(IoDevice, Box#mp4_raw_box.start + 8,  Box#mp4_raw_box.start + Box#mp4_raw_box.size_base - 8, []).


read_boxes(IoDevice, Pos, End, Boxes) when (End > Pos) or (End == 0) ->
    case file:pread(IoDevice, Pos, 8) of
        {ok, <<Size:32/integer, Type:4/binary>>} ->
            Box = #mp4_raw_box{type=binary_to_list(Type), size_base=Size, start=Pos},
            case isContainer(Box) of
                true ->
                    ChildrenBoxes = read_boxes(IoDevice, Box),
                    read_boxes(IoDevice, Pos + Size, End, Boxes ++ [[Box|ChildrenBoxes]]);
                _ ->
                    read_boxes(IoDevice, Pos + Size, End, Boxes ++ [Box])
            end;
        eof ->
            Boxes
    end;

read_boxes(_IoDevice, _Pos, _End, Boxes) ->
    Boxes.


%% Parse MP4 Box
parse_boxes(Boxes, IoDevice) ->
    lists:map(fun(X) 
                    when is_record(X, mp4_raw_box) ->
                      parse_box(X, IoDevice);
                 (X) ->
                      parse_boxes(X, IoDevice)
              end, Boxes).

parse_box(RawBox = #mp4_raw_box{type = "stsd"}, IoDevice) ->
    case file:pread(IoDevice, RawBox#mp4_raw_box.start, RawBox#mp4_raw_box.size_base ) of
        {ok, <<_Size:32/integer, _Type:4/binary, 
               _Version:16/integer, _Flags:2/binary, 
               CountEntries:32/integer, EntryData/binary>>} ->
            stsd_entries(CountEntries, EntryData, [])
    end;


parse_box(_RawBox = #mp4_raw_box{}, _IoDevice) ->
    [].

%% Parse StSd box
stsd_entries(CountEntries, <<Size:32/integer, "avc1", EntryData/binary>>, Entries) ->
    AvcSize = Size - 86,
    <<_Reserved:6/binary,
      _RefIndex:16/integer, 
      _Unknown1:16/binary, 
      Width:16/integer,
      Height:16/integer,
      HorizRes:32/integer,
      VertRes:32/integer,
      _FrameCount:16/integer,
      _CompressorName:32/binary,
      _Depth:16/integer, 
      _Predefined:16/integer,
      _Unknown:4/binary,
      AvcEntry:AvcSize/binary,
      Data/binary>> = EntryData,
    AvcEntries = parse_avc(AvcEntry),
    Entry = #stsd_entry{ type = avc1, size = Size,
                         width = Width, height = Height,
                         horiz_res = HorizRes, vert_res = VertRes,
                         entries = AvcEntries
                       },
    stsd_entries(CountEntries - 1, Data, Entries ++ [Entry]);

stsd_entries(_, _, Entries) ->
    Entries.

%% Parse Avc box
parse_avc(<<Size:32/integer, "avcC",  Data/binary>>) ->
    <<Version:8/integer,
      ProfileIndication:8/integer,
      ProfileCompatibility:8/integer,
      Level:8/integer,
      _Reserver:6/binary,
      _/binary>> = Data,
    AvcEntry = #avc_entry{ size = Size, version = Version,
                           profile_indication = ProfileIndication,
                           profile_compatibility = ProfileCompatibility,
                           level = Level
                         },
    AvcEntry.

